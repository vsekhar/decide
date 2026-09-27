---
priority: p2
type: feature
created: 2026-09-27T16:49:44-04:00
updated: 2026-09-27T16:49:44-04:00
---

# Read the API key from standard input: --api-key - or a bare --api-key prompts with echo off at a terminal

## Objective

Keep the API key out of shell history and `ps`. `--api-key -` reads the key from standard input, and so does `--api-key` with no value. At a terminal the tool prints `API key: ` on stderr and reads one line with echo off; from a pipe it reads one line with no prompt. Both the run line and `--set-config` take it. Setup becomes:

```sh
$ brew install vsekhar/tap/decide
$ decide --set-config --model typesafe:jev-latest --api-key -
API key:
```

and a script does `printf '%s' "$KEY" | decide --set-config --api-key -`. The README stops recommending an inline key for setup, and its `DECIDE_API_KEY` typo becomes `DECIDE_MODEL_API_KEY`.

## Context

Requested by the user on 2026-09-27 after asking how command-line tools take secrets. The idioms: a prompt with echo off (`aws configure`, `gh auth login`), the secret on standard input (`docker login --password-stdin`, `gh auth login --with-token`), the environment for CI, and a config file at mode 0600. decide already has the last two: `DECIDE_MODEL_API_KEY`, the providers' own variables, and `--set-config`, which writes the home config at 0600 in a 0700 directory. What it lacks is a way to type or pipe the key without putting it in argv. The user chose the two triggers: `-`, which already means standard input for `--context` and `--questions`, and a bare `--api-key`.

How the code stands (HEAD eb35321, 0.4.0):

- `CommandLineParser` reads `--api-key` through the shared `flagValue(of:token:arguments:index:)` in two places, the run loop and `parseSetConfig`, then `setting(_:of:)` refuses an empty or blank value with `--api-key is empty`. `flagValue` takes the next token verbatim, so today `--api-key --project` makes `--project` the key, and `--api-key` as the last token is `--api-key needs a value`.
- `Invocation.apiKey: String?` and `SetConfig.apiKey: String?` hold the key. `Invocation.applied(to:)` lays it over `DECIDE_MODEL_API_KEY`; `Decide.run` calls that right before `ModelConfiguration(environment:).makeModel()`. `Decide.setConfig` builds the pairs through `settings(of:)`.
- `StandardInputReading` (wip/cba) has `readToEnd()` and `readLine()`; `StandardInput` reads lines with `read(2)`. `Decide.run` takes `standardInput: any StandardInputReading`, wraps `readToEnd` to record a read, and refuses a second `-` after the parse with `CommandLineParser.standardInputTwice`. The parser refuses two `-` contexts with the same message.
- `QuestionFile.check` refuses `--api-key` in a question file already.
- `ExitCode.message(for:)` and `code(for:)` map each error type; `ContextLoadError` is the newest.

## Location

- `Sources/DecideCore/Invocation.swift`: `KeySource`, the type of `Invocation.apiKey` and `SetConfig.apiKey` (the latter lives in CommandLineParser.swift), `readsStandardInput` on `Invocation`.
- `Sources/DecideCore/CommandLineParser.swift`: `keySource(token:arguments:index:)`, both call sites, the `-` twice check across the key and the context.
- `Sources/DecideCore/StandardStreams.swift`: `isTerminal` and `readSecretLine()` on the protocol and on `StandardInput`.
- `Sources/DecideCore/Decide.swift`: `APIKeyError`, `readAPIKey(...)`, the read in `run` before `applied(to:)`, the read in `setConfig`, the once-per-run check, the usage text.
- `Sources/DecideCore/ExitCode.swift`: the `APIKeyError` cases.
- `README.md`: Install and Setup, Command line configuration. `TESTING.md`: the terminal check.
- Tests: `CommandLineParserTests`, `InvocationTests`, `DecideRunTests`, `ExitCodeTests`.

## Approach

**Grammar.** A new parser helper reads the value of `--api-key` in both places:

- `--api-key <key>` and `--api-key=<key>` are the key, as today. An empty or blank key is still `--api-key is empty`, including `--api-key=` and `--api-key ""`: an unset shell variable must fail loudly, not wait on standard input.
- `--api-key -` and `--api-key=-` read standard input.
- `--api-key` followed by no token, or by a token that starts with `-` (a flag, or `-q`), also reads standard input, and that token stands on its own. So `--set-config --api-key --project` is the key from standard input plus `--project`, which the project rule then refuses as today.

`public enum KeySource: Sendable, Equatable { case value(String); case standardInput }`, in Invocation.swift, with doc comments: `.value` is "The key itself, from `--api-key <key>`"; `.standardInput` is "One line of standard input, from `--api-key -` or `--api-key` with no value: a prompt with echo off at a terminal, one line from a pipe." `KeySource` is `ExpressibleByStringLiteral` (`"k"` is `.value("k")`), so every existing `apiKey: "k"` in tests compiles unchanged. `Invocation.apiKey` and `SetConfig.apiKey` become `KeySource?`. `Invocation.applied(to:)` lays a `.value` over the environment and leaves it alone for `.standardInput`, which the run resolves first. `Invocation.readsStandardInput` is true when the context reads it or the key does.

**Once per run.** The parser refuses `--api-key -` beside a `-` context with `standardInputTwice`. `Decide.run` checks `invocation.readsStandardInput` where it checks the context today, so `--api-key -` with `--questions -` is refused too. `--each` with `--api-key -` and a `-` context is `-` twice; with no `-` context the parser's `eachNeedsStandardInput` fires.

**Reading.** `StandardInputReading` gains `var isTerminal: Bool { get }` ("Whether standard input is a terminal, so a key can be asked for with a prompt and echo off") and `func readSecretLine() throws(ConfigReadError) -> String?` ("One line with the terminal's echo off when standard input is a terminal, else one line as `readLine` gives it; nil at end of file"). `StandardInput.isTerminal` is `isatty(STDIN_FILENO) == 1`. `readSecretLine` at a terminal takes `tcgetattr` of `STDIN_FILENO`, clears `ECHO` in `c_lflag` (cast through `tcflag_t`, because `ECHO` is `Int32` and `c_lflag` is `tcflag_t` on both platforms), sets it with `TCSAFLUSH`, restores the saved attributes in a `defer`, and calls `readLine()`; canonical mode stays on, so Enter ends the line. Off a terminal it is `readLine()`.

`Decide.readAPIKey(from:stderr:)` prints `API key: ` with no newline on stderr when `isTerminal`, calls `readSecretLine()`, prints a newline on stderr when `isTerminal` (echo off swallowed the user's Enter), trims surrounding whitespace, and gives the key. `APIKeyError` (internal, Decide.swift): `.empty` is `standard input holds no API key` (an empty line or end of file before any line), `.unreadable` is `cannot read standard input`, `.notUTF8` is `standard input is not valid UTF-8`; `ExitCode` maps each to `Error: ` plus the message and code 10. No prompt from a pipe, so a script's stderr stays clean.

`run` resolves the key after the config files load and before `applied(to:)`: when `invocation.apiKey == .standardInput`, read it and set `invocation.apiKey = .value(key)`; a throw prints the message and returns 10. `setConfig` does the same before `settings(of:)`, so it gains a `standardInput` parameter. A `--set-config` run reads no config chain, as today.

**Usage text**, the `--api-key` entry:
```
  --api-key <key>                The API key for this run. Wins over the environment
                                 and every config file. --api-key - reads the key from
                                 standard input: a prompt with echo off at a terminal,
                                 one line from a pipe. --api-key with no value does the
                                 same.
```

**README.** Install and Setup:
```sh
$ brew install vsekhar/tap/decide
$ decide --set-config --model typesafe:jev-latest --api-key -
API key:
```
followed by: "`--api-key -` asks for the key with echo off, so it stays out of your shell history. A script pipes it: `printf '%s' "$KEY" | decide --set-config --api-key -`. You can also set `DECIDE_MODEL` and `DECIDE_MODEL_API_KEY` in the environment, or write them to `$HOME/.config/decide/config`." Under Command line configuration, keep the inline example and add: "The inline form is for scripts, where `"$KEY"` never reaches your history. For a key you type, use `--api-key -`."

**TESTING.md**, under "What the suite cannot see": the terminal path reads the real descriptor. With `HOME` set to an empty temp directory: `decide --set-config --api-key -` at a terminal shows `API key: `, echoes nothing while you type, and writes the key to `$HOME/.config/decide/config`; `printf 'k\n' | decide --set-config --api-key -` shows no prompt and writes `k`.

## Out of Scope

- A keychain or credential helper.
- Reading the key from a file path (`--api-key @path`): the pipe covers it.
- Treating `--api-key=` or `--api-key ""` as a request to read standard input.
- Any change to the environment variable names or the config file format.

## Tests

- Parser: `--api-key -` and `--api-key=-` give `.standardInput` on a run line and under `--set-config`; a bare `--api-key` as the last token gives `.standardInput`; `--set-config --api-key --project` gives `.standardInput` and `project`, which the project rule then refuses; `--api-key -q` on a one-yes/no-question line gives `.standardInput` and `quiet`; `--api-key=` and `--api-key ""` are still `--api-key is empty`; `--api-key k` still gives `.value("k")`; `--api-key -` with `--context -` is `standardInputTwice`; `--api-key` twice is still refused.
- Invocation: `applied(to:)` lays `.value` over the environment and leaves it alone for `.standardInput`; `readsStandardInput` is true for the key alone.
- ExitCode: the three `APIKeyError` cases give their messages and 10.
- Run (`ScriptedInput` gains `isTerminal`, default false, and `readSecretLine` gives its next line): `--set-config --api-key -` with `ScriptedInput("secret\n")` writes `DECIDE_MODEL_API_KEY = "secret"` to the temp home config, prints nothing on stdout, nothing on stderr, exits 0, and read once; the same with `isTerminal: true` prints `API key: \n` on stderr and nothing else; `ScriptedInput("  secret  \n")` writes `secret`; `ScriptedInput("")` and `ScriptedInput("\n")` exit 10 with `Error: standard input holds no API key` and write no file; `ScriptedInput(failing: .unreadable)` and `.notUTF8` exit 10 with their messages; `--set-config --api-key --project` exits 10 with the project message and reads nothing; a run line `--api-key -` with a scripted model and `ScriptedInput("k\n")` prints its answer, reads once, and with `isTerminal: true` shows the prompt on stderr before the answer's stderr; `--api-key -` with `--questions -` exits 10 with `standardInputTwice` and the usage text; a run whose model is malformed (`--model nosuch --api-key -`) exits 10 after reading the key (the key is applied before the model is made), or before it if the implementer orders the reads the other way, and the test pins whichever the code does; the usage text shows the new entry.
- No live test: the wire does not change.

## Related Issues

- wip/4c6 (`-` reads standard input; the once-per-run rule), wip/cba (`StandardInputReading`, the line reader).

## Acceptance Criteria

- [ ] `--api-key -`, `--api-key=-`, and `--api-key` with no value read one line from standard input on a run line and under `--set-config`; at a terminal the prompt shows on stderr and the key does not echo; from a pipe there is no prompt.
- [ ] An empty key, end of file, or standard input that does not read exits 10 with its message and writes no config.
- [ ] The once-per-run rule covers the key: `--api-key -` beside `--context -` or `--questions -` is refused with the existing message.
- [ ] `--api-key=` and `--api-key ""` are still `--api-key is empty`, and `--api-key <key>` is unchanged.
- [ ] `--help`, the README's Install and Setup, and Command line configuration describe the flag; the README names `DECIDE_MODEL_API_KEY`, not `DECIDE_API_KEY`; TESTING.md has the terminal check.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.
