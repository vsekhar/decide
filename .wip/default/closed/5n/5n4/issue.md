---
priority: p2
type: feature
created: 2026-09-27T16:49:44-04:00
updated: 2026-09-27T17:32:31-04:00
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

---

_📝 Noted on 2026-09-27 16:58:51-04:00 @ git:eb1013f+local_

Design record (2026-09-27), the choices the issue left open, all against HEAD after origin/main (d5aa623) is merged in:

1. Order in run: config files load, then the key is read when apiKey == .standardInput, then applied(to:), then the model is made. So --model nosuch --api-key - reads the key first and reports the bad model after; the run test pins reads == 1. Rationale: one do/catch on the key, the issue's stated order, and --set-config behaves the same (read the key, then settings(of:) refuses a bad model). Refusing the model before the prompt would need a second ModelConfiguration(environment:) pass; not worth it for a rare typo.

2. KeySource has no value accessor. applied(to:) and settings(of:) match 'case .value(let key)?' and leave .standardInput alone, which run and setConfig resolve to .value before either is called. A comment at settings(of:) says so.

3. Parser helper keySource(token:arguments:index:) -> KeySource?, private, beside flagValue. nil unless the token is --api-key or --api-key=<rest>. --api-key then end of tokens: .standardInput. --api-key then '-': consumed, .standardInput. --api-key then a token starting with '-': not consumed, .standardInput. --api-key then anything else: consumed, setting(_:of:) (so '' and blank are '--api-key is empty'). --api-key=-: .standardInput. --api-key=<rest>: setting(rest). Both call sites (the run loop and parseSetConfig) use it; flagValue stays for every other flag.

4. The parser's twice check sits right after context(from:) and before the --each checks: apiKey == .standardInput with a context that reads standard input throws standardInputTwice. Decide.run's post-parse check becomes invocation.readsStandardInput (context or key), so --questions - beside --api-key - is refused there.

5. StandardInput.readSecretLine: off a terminal it is readLine(). At a terminal: tcgetattr, copy, c_lflag &= ~tcflag_t(ECHO), tcsetattr TCSAFLUSH, defer restore with '_ =' (warnings-as-errors), then readLine(). A tcgetattr or tcsetattr failure is .unreadable. isTerminal is isatty(STDIN_FILENO) == 1.

6. readAPIKey(from:stderr:) in Decide: prompt 'API key: ' with no terminator on stderr when isTerminal; the newline after the read is in a defer, so it lands even when the read throws and the error starts on its own line. nil (EOF) or an empty trimmed line is APIKeyError.empty. ConfigReadError maps .unreadable -> .unreadable, .notUTF8 -> .notUTF8. APIKeyError is internal in Decide.swift with a message property; ExitCode maps it like ContextLoadError (code 10, 'Error: ' + message).

7. setConfig gains standardInput: any StandardInputReading and resolves the key before settings(of:) and target(of:). --set-config --api-key --project never reads: the parser refuses it first.

8. ScriptedInput in DecideRunTests gains isTerminal (init parameter, default false) and readSecretLine(), which is readLine(), so it counts as one read.

9. README: the Install and Setup block shows 'decide --set-config --model typesafe:jev-latest --api-key -' then 'API key:'; the sentence after it replaces d5aa623's '(alternatively, ...)' line, which had the DECIDE_API_KEY typo. Command line configuration keeps its inline example and adds one sentence. TESTING.md gets the terminal check under 'What the suite cannot see'. .claude/skills/decide/SKILL.md line 43 keeps '--api-key <key>': a skill's setup line is for an agent, which has no terminal; out of scope.

---

_📝 Noted on 2026-09-27 17:01:05-04:00 @ git:eb1013f+local_

Branch note (2026-09-27): worktree-5n4-api-key-stdin is based on eb1013f, which origin/main now points at (reflog: 555b3fe -> d5aa623 -> eb1013f by pushes). d5aa623 'Alternate setup', the commit that held the DECIDE_API_KEY typo, is on no branch any more, so the README has no typo line to fix; the new Install and Setup paragraph names DECIDE_MODEL_API_KEY.

---

_📝 Noted on 2026-09-27 17:26:40-04:00 @ git:eb1013f+local_

Design record addendum (2026-09-27), after verification.

10. Signals at the prompt. A fatal signal (Ctrl-C, kill, a closed terminal) skips the defer that restores the terminal, so echo would stay off in the shell after Ctrl-C at 'API key: ' (bash does not reset it; zsh does). readSecretLine now installs a handler for SIGINT, SIGTERM, and SIGHUP for the length of the read: it puts the saved attributes back with TCSANOW, resets the signal to SIG_DFL, and raises it again, so the exit status is still the signal's. The saved attributes live in a nonisolated(unsafe) static, written only by the reading thread before the handlers go in and after they come out; the handler only reads it. The defer restores the terminal first, then the previous handlers, then clears the static. No unit test drives a signal on a pty; TESTING.md has the manual check (stty -a shows echo on after Ctrl-C).

11. TCSAFLUSH stays: it drops input typed before the prompt, which echoed while echo was still on, as getpass does. Automation that pushes the key into a pty before the prompt loses it; a pipe is the automation path, and a pipe never sees the prompt.

12. By decision 3, a key that starts with '-' cannot be given as '--api-key -abc' (that reads standard input, then '-abc' is an unknown flag); '--api-key=-abc' still works. Accepted: no provider issues such keys.

13. README, Command line configuration: the sentence names ps as well as history, since the inline key shows in ps for the run's length. The Standard input section's prose names the key among the three things '-' can read.

---

_📝 Noted on 2026-09-27 17:32:04-04:00 @ git:eb1013f+local_

Second verification pass (2026-09-27): the Ctrl-C fix held on a real pty (SIGINT and SIGTERM at the prompt both put echo back and ended the process by the signal, status 2 and 15). Three minor findings, routed as follows.

14. The handlers now go in, and the saved attributes are stored, before echo goes off, so a signal in the microseconds between the two steps finds the handler in place. If the echo-off tcsetattr then fails, the defer still restores the terminal and the handlers before the throw.

15. Accepted, not fixed: the handler replaces an inherited SIG_IGN, so a process that started with SIGINT or SIGHUP ignored would die at the prompt where it would have gone on. The usual idiom (leave a signal alone when its old handler is SIG_IGN) needs a pointer comparison Swift only does through unsafeBitCast, and the case needs a terminal on stdin in a process that ignores the signal, which a shell never produces: a non-interactive background job has stdin on /dev/null, and nohup redirects a terminal stdin. Revisit if a real caller hits it.

16. The run-line form --api-key --project now has a parser test (it is '--project needs --set-config', the bare key reads standard input). TESTING.md's Ctrl-C check says to run it from bash, because zsh resets the terminal itself and would pass the check without the handler.

Not run: the live suite (the key file is outside the worktree and the session may not copy it; the wire does not change, so it is a regression check) and the Linux build (no docker here). Linux compiles by reasoning: the code never names the platform's handler type, SIG_DFL and the signal numbers come from Foundation on both, and the termios names are the same ones the read loop already uses.

---

_📝 Noted on 2026-09-27 17:32:31-04:00 @ git:eb1013f+local_

Summary (2026-09-27): implemented --api-key -, --api-key=-, and a bare --api-key on the run line and under --set-config. KeySource (value or standardInput, string-literal expressible) replaces String? for Invocation.apiKey and SetConfig.apiKey. Parser: a keySource helper for both call sites, and the once-per-run check beside a - context; Decide.run checks invocation.readsStandardInput after the questions expansion. StandardInputReading gains isTerminal and readSecretLine; StandardInput turns ECHO off through termios, with SIGINT, SIGTERM, and SIGHUP handlers that put the terminal back and re-raise. Decide.readAPIKey prompts 'API key: ' on stderr at a terminal, ends the line after the read, trims, and maps to APIKeyError (empty, unreadable, notUTF8; exit 10). README Install and Setup and Command line configuration, the usage entry, and TESTING.md's terminal and Ctrl-C checks are updated. 595 offline tests pass; the build is clean with warnings as errors. Not run here: the live suite (the key file is outside the worktree; the wire does not change) and the Linux build (no docker). A worker implemented from the brief and closed the verifier's test gaps; the verifier ran two passes, with pty probes of the echo and the signal path.
