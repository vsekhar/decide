---
priority: p2
type: task
created: 2026-09-21T20:15:50-04:00
updated: 2026-09-23T00:10:16-04:00
blocked-on:
  - mia
  - rvj
---

# Add --set-config with --model, --api-key, and --project: write settings into a config file and keep the rest

## Objective

`decide --set-config DECIDE_MODEL="typesafe:jev-latest"` writes that key into the home config file, changing only that line, and `--project` writes the working directory's `.decide/config` instead. Every other byte of the file, comments included, stays as it was.

## Context

Part of wip/chc; blocked on wip/mia (the parser is the editor's check) and wip/rvj (the places). Decided with the user on 2026-09-21: the tool writes config as well as reads it. With the TOML subset, a targeted line editor is small and keeps comments, which a re-encode would drop; this is the `git config` model. The flag runs alone, because a bare token is a question in this tool and `decide config set` would be asked of the model. The default target is the home file, as `npm config set` and `gh config set` do; writing a project file by default would create `.decide/` in whatever directory the user happens to be in. The trust rule from wip/rvj holds on write: `DECIDE_MODEL_API_KEY` may not go into a project file.

## Design

- Parser. `--set-config KEY=VALUE` and `--set-config=KEY=VALUE`, split at the first `=` after the flag's own; repeatable; `--project` is a bare flag. `ParseResult` gains `case setConfig(SetConfig)` with `public struct SetConfig: Equatable, Sendable { public var entries: [(key: String, value: String)] as an array of a small Equatable struct; public var project: Bool }`. Rules and messages: any other token on the line (`--context`, a question, a kind flag, `--min-confidence`, `-q`) is `--set-config runs alone`; `--project` without `--set-config` is `--project needs --set-config`; no `=` in the value is `--set-config needs KEY=VALUE`; an unknown key uses the parser's wording, `unknown key "X"; the keys are DECIDE_MODEL and DECIDE_MODEL_API_KEY`; an empty value is `DECIDE_MODEL is empty`; the same key twice on one line is `--set-config sets DECIDE_MODEL twice`; `DECIDE_MODEL_API_KEY` with `--project` is `DECIDE_MODEL_API_KEY is allowed only in the home config, not in a project's`. `--help` still wins anywhere.
- Target. Home: the first home path from `ConfigFiles.paths`, `<xdg>/decide/config`; `HOME` unset or blank is `HOME is not set, so there is no home config`. Project: `<currentDirectory>/.decide/config`.
- Editor, pure, in `ConfigFile`: `public static func setting(_ entries: [(key, value)], in text: String, path: String) throws(ConfigError) -> String`. Parse the existing text first; an invalid file is the usual error, and the user fixes it by hand. For each entry: when the key has a line, replace that line's value with the basic-string encoding of the new value and keep the key's spelling, the spacing around `=`, any trailing comment, and a CRLF ending if the line had one; when it has none, append `KEY = "value"` on its own line at the end, after making sure the text ends with a newline (an empty text gets no leading blank line). Encoding: `"` to `\"`, `\` to `\\`, newline to `\n`, tab to `\t`, carriage return to `\r`; any other control character is `value has a control character`. Then parse the result as a check that it round-trips to the new values.
- Writing, in `Decide.swift` (private): create the parent directories (`~/.config/decide` with mode 0700); read the current text if the file exists (missing means empty; unreadable or not UTF-8 is the loader's error); compute the new text; write it to a temporary file in the same directory; set mode 0600 for the home file; rename over the target. Success prints nothing and returns 0. Any failure prints `Error: <path>: <reason>` and returns 10, and the target is untouched.
- `Decide.usage` gains two lines before `--help`: `--set-config K=V        Write a key to the home config and exit.` and `--project              With --set-config, write ./.decide/config instead.` `README.md`'s Configuration files subsection (from wip/rvj) gains the `--set-config` example and the `--project` sentence.

## Location

- `Sources/DecideCore/CommandLineParser.swift`, `ConfigFile.swift`, `Decide.swift`.
- `README.md` Setup.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `ConfigFileTests.swift`, `DecideRunTests.swift`.

## Tests

- Parser: both flag forms; repeat gives two entries; `--project`; the alone rule against a question, `--context`, and `-q`; `--project` alone; no `=`; unknown key; empty value; the same key twice; the key with `--project`; a value containing `=` keeps everything after the first.
- Editor, pure: replacing keeps every other line byte for byte, comments, spacing, a trailing comment on the edited line, and CRLF; appending to empty text, to text without a trailing newline, and to comment-only text; escaping of each special character; a control character errors; an invalid existing file errors with its line; two entries in one call; the result parses back to the new values.
- Run level, temp `HOME`: writes the home file with mode 0600 and creates the directories; a second write changes only the one line (compare the whole text); `--project` writes `<currentDirectory>/.decide/config`; a file written here reads back through `ConfigFiles.load` with the same value, including a value with a quote and a backslash; the key to a project is refused with exit 10 and no file created; success prints nothing on stdout or stderr and exits 0; an existing malformed file is refused with its line and left as it was.
- By hand, once: `--set-config` in a temp `HOME`, then a real run with the environment cleared picks the model up. One paid request.

## Related Issues

Parent wip/chc. Blocked on wip/mia and wip/rvj. wip/brs set the pattern for a flag that runs alone (`--quiet` is not one, but its grammar checks are the model).

## Acceptance Criteria

- [ ] `decide --set-config DECIDE_MODEL="typesafe:jev-latest"` creates or edits the home file, and a later run with no environment variables uses that model.
- [ ] A second `--set-config` leaves every other byte of the file unchanged, comments included.
- [ ] `--project` writes `./.decide/config`; `DECIDE_MODEL_API_KEY` with `--project` is refused and nothing is written.
- [ ] Bad input exits 10 with a message and leaves the target untouched; success prints nothing and exits 0.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, `swift test --skip DecideLive` passes, and `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-22 22:26:34-04:00 @ git:c568c93+local_

Observed 2026-09-22: README commit c568c93 (the user's rewrite) put a TODO in "Install and Setup": "convert these to `decide --setconfig --model jev-latest --api-key abc123...`". That shape (one flag plus --model and --api-key) differs from this issue's `--set-config KEY=VALUE` with `--project`. Before implementing, confirm with the user which shape they want; the issue's design was decided 2026-09-21 and the TODO is newer.

---

_📝 Noted on 2026-09-22 22:47:16-04:00 @ git:c568c93+local_

From mia's verification 2026-09-22: `ConfigFile.unknownKeyProblem(_:)` interpolates its argument as given; the parser bounds the key to `A-Z a-z 0-9 _ -` before calling it. The `--set-config` parser must do the same check before it names a user-supplied key in a message, or the message can carry arbitrary text from the command line.

---

_📝 Noted on 2026-09-22 23:43:49-04:00 @ git:8c0b89e+local_

User decision 2026-09-22: the flag is `--set-config --model <provider:model> --api-key <key>`, hyphenated, with `--project`. This replaces the issue's `--set-config KEY=VALUE` design and resolves the README TODO. Design record for the remaining scope (wg5 built the editor):

**Parser.** `--set-config` is a bare flag. Pre-scan: after the `--version` and `--help` checks, `if arguments.contains("--set-config") { return .setConfig(try parseSetConfig(arguments)) }`, so the set-config line has its own small grammar. `ParseResult` gains `case setConfig(SetConfig)`; `public struct SetConfig: Equatable, Sendable { public var model: String?; public var apiKey: String?; public var project: Bool }` with a public init. In `parseSetConfig`, every token is one of: `--set-config` (once; again → "--set-config was given twice"); `--project` (once; again → "--project was given twice"); `--model <v>` or `--model=<v>` via `flagValue` (once; again → "--model was given twice"; a value that is empty or only whitespace → "--model is empty"); `--api-key <v>` or `--api-key=<v>` the same way ("--api-key was given twice", "--api-key is empty"). Any other token → "--set-config runs alone". After the loop: neither `--model` nor `--api-key` → "--set-config needs --model or --api-key"; `--api-key` with `--project` → "--api-key is allowed only in the home config, not in a project's". In the main grammar (no `--set-config` on the line), `--model`, `--api-key`, and `--project` each throw "<flag> needs --set-config" (`--model=x` too, matched by prefix). Values are not trimmed; `ModelConfiguration` trims the model later and the key is written as given.

**Targets.** Two public helpers on `ConfigFiles`, which `paths` uses too: `homeFile(environment:) -> String?`, the first home path (`<xdg>/decide/config`) or nil when HOME is unset or blank; `projectFile(in currentDirectory: String) -> String`, `<normalized currentDirectory>/.decide/config`. Also `public static func error(_ reason: ConfigReadError, at path: String) -> ConfigError` holding the two line-0 problems, used by `merge` and by the writer.

**Run step**, in `Decide.run`, `case .setConfig(let request)` handled right after the `switch parsed` (before any config read; a set-config run reads no config chain): (1) when `request.model` is set, `try ModelConfiguration(environment: [ModelConfiguration.modelVariable: model])`; a `ConfigurationError` prints its usual message and returns 10, so a malformed model or unknown provider never reaches a file. (2) The target: `--project` needs `currentDirectory`; nil → "Error: --project has no working directory", 10. Home: `ConfigFiles.homeFile(environment:)`; nil → "Error: HOME is not set, so there is no home config", 10. (3) Read the current text with `readConfigFile`: nil → ""; a `ConfigReadError` → `ConfigFiles.error(_:at:)` printed through `ExitCode.message`, 10. (4) `ConfigFile.setting(pairs, in: text, path: path)` with pairs `[(DECIDE_MODEL, model)]` and/or `[(DECIDE_MODEL_API_KEY, key)]` in that order; a `ConfigError` prints and returns 10. (5) Write, in a private `writeConfigFile(_ text: String, to path: String, isHome: Bool) throws`: create the parent directory with `createDirectory(atPath:withIntermediateDirectories:attributes:)`, mode 0o700 for the home file's directory and default otherwise; write the text to `<dir>/.config.<UUID>.tmp` with `Data.write(to:)`; set mode 0o600 on it for the home file; `rename(2)` it over the target (POSIX `rename`, atomic on both platforms; `FileManager.moveItem` refuses an existing destination); on any failure remove the temp file and throw. The run prints "Error: <path>: <error.localizedDescription>" and returns 10; the target is untouched. (6) Success prints nothing on either stream and returns 0.

**Usage text**, four lines before `--help, -h`, in the flag column style:
```
  --set-config           Write settings to the home config and exit.
  --model <model>        With --set-config, the model to write, provider:model.
  --api-key <key>        With --set-config, the key to write. Home config only.
  --project              With --set-config, write ./.decide/config instead.
```
and the Environment paragraph's last sentence gains: "--set-config edits one line and keeps the rest."

**README**, "Install and Setup": the first block becomes
```sh
$ brew install vsekhar/tap/decide

# Save the model and your key to ~/.config/decide/config
$ decide --set-config --model typesafe:jev-latest --api-key abc123...

# Or set them in the environment, which wins over every config file
$ export DECIDE_MODEL=typesafe:jev-latest    # or openrouter:typesafe/jev-1.13
$ export DECIDE_MODEL_API_KEY=abc123...
```
(the TODO comment goes). The second block gains a first command, `$ decide --set-config --model typesafe:jev-latest --project`, before `$ cat .decide/config`. The paragraph after it gains a last sentence: "`--set-config` edits one line and keeps the rest of the file, comments included."

**Tests.** Parser (`CommandLineParserTests`): both value forms for `--model` and `--api-key`; `--project`; the alone rule against a question, `--context`, `-q`, and `--option`; each of the three flags alone → "needs --set-config"; `--set-config` alone; each flag twice; `--model=` empty and `--model " "`; `--api-key` with `--project`; `--set-config --help` → `.help`; `--set-config --version` → `.version(alone: false)`; a value holding `=` keeps everything after the first. Run level (`DecideRunTests`, reusing `ConfigTree` with `HOME` inside it, `currentDirectory: tree.sub`): writing the home file creates `<home>/.config/decide` (mode 0700) and the file (mode 0600), stdout and stderr empty, exit 0; a second `--set-config --model` on a file with a comment line and both keys changes only the model line (compare the whole text); `--project` writes `<sub>/.decide/config`; a value with a quote and a backslash written by `--api-key` reads back through `ConfigFiles.load` unchanged; `--api-key --project` exits 10 and creates no file; an existing malformed home file exits 10 naming its line and is byte-identical after; `--model jev-latest` exits 10 with the DECIDE_MODEL message and writes nothing; `environment: [:]` (no HOME) exits 10 with the HOME message; `currentDirectory: nil` with `--project` exits 10. By hand, one paid request: `--set-config --model typesafe:jev-latest --api-key <key>` in a temp HOME, then a real run from an empty directory with the four variables unset and that HOME → yes, exit 0.

---

_📝 Noted on 2026-09-22 23:55:41-04:00 @ git:8c0b89e+local_

Implemented 2026-09-22 by a worker from the "User decision" design record; diff read in the main context and matches. Worker's choices, accepted: `SetConfig.init` defaults `project` to false like `Invocation.init`; private `setting(_:of:)` and `setConfigFlag(_:)` in the parser; `settings(of:)` and `target(of:environment:currentDirectory:)` in `Decide`, the target failures as `UsageError`s printed without usage text; `homePaths` derives HOME itself so `homeFile` reuses it; `ConfigTree` gained `homeDirectory` and `mode(_:)`. One revision from the main context, done by the worker: the temp file is created with `open(2)` at its final mode (0600 for the home file), not written at the default mode and chmod-ed after, so a key is never readable by others even for an instant when the directory already existed with a permissive mode; `open` and `rename` failures share a `posixError()` helper. Known wording: `--api-key --project` is a parser error, so it prints the usage text after the message like every usage error. Checks: build with warnings as errors clean; offline suite 236/236 (10 parser, 3 ConfigFiles, 9 run-level new); whole suite with .env sourced 238/238; by hand, the binary wrote a temp HOME's config at 0600 in a 0700 directory, a real run with the four variables unset then answered yes with exit 0, `--project` wrote a one-line project file, and `--api-key --project` was refused with exit 10 (two paid requests, the script ran twice). Dead-code check by hand: every added symbol has a caller (`ConfigFiles.error` by `merge` and the writer; `homeFile`/`projectFile` by `target`; `posixError` twice); nothing removed; no unused import or parameter. Sent to the verifier.

---

_📝 Noted on 2026-09-23 00:10:16-04:00 @ git:8c0b89e+local_

Verified 2026-09-23: all five acceptance criteria hold. The verifier proved the write-then-run path end to end with one paid request, every failure path leaving the target untouched, the modes on fresh and pre-existing directories, a 200-round round-trip soak through the loader, and the full grammar table. Its notes and the fixes in the main context: (1) no test saw the atomic write → new test "A write makes a permissive home config the owner's alone" (a 0644 file becomes 0600), shown to fail against a direct-write mutant; (2) no test saw that a set-config run reads no chain → new test "A set-config run reads no config chain" (a broken parent file does not stop the write), shown to fail against a chain-reading mutant; (5) `paths` now builds each project path with `projectFile(in:)`, one expression; (6) the writer's failure message now goes through `ExitCode.message(for: ConfigError(path:line: 0:problem:))`, so it is one line like every other. Left on the record: the parser is the single gate for `--api-key` with `--project` and the private run step relies on it (no public API takes a SetConfig); a symlinked config file is replaced by a regular file (logged on chc); `--set-config --api-key --project` with the value forgotten stores "--project", the tool's convention for every value flag; the diff adds the package's first raw POSIX calls with only `import Foundation`, which macOS builds clean and the Linux CI job will check. Offline suite 238/238.
