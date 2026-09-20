---
priority: p2
type: task
created: 2026-09-20T18:13:04-04:00
updated: 2026-09-20T18:30:37-04:00
blocked-on:
  - 28j
  - wh2
  - mfa
---

# Wire the entry point: load context, decide, print answers

## Objective

Connect the parser, the configuration, and the runner into the `decide` binary: read the context (literal or `@file`), run the questions, print one answer id per line to stdout in question order, and exit with the README's codes. Add a live test against Jev in the library's style, and update the README's Setup section to the `provider:model` scheme.

## Context

Part of wip/v7x. Blocked on wip/28j (parser), wip/wh2 (runner), and wip/mfa (configuration and exit codes). After this issue the README's classification and batch examples work end to end:

```sh
$ decide --context @ticket.txt "Which team handles this ticket?" --option shipping --option billing --option returns
returns
```

## Approach

- `Sources/DecideCore/Decide.swift`: replace the stub from wip/s47 with
  `public static func run(arguments: [String], environment: [String: String], model: (any DecisionModel)? = nil, stdout: inout some TextOutputStream, stderr: inout some TextOutputStream) async -> Int32` (or an equivalent shape that lets tests inject a model and capture both streams). Order inside `run`:
  1. Parse the arguments (wip/28j). `.help` prints the usage text to stdout and returns 0. A `UsageError` prints `Error: <message>` and the usage text to stderr and returns 2. Empty arguments do the same.
  2. Build the configuration from the environment (wip/mfa) unless a model was injected. A `ConfigurationError` prints its message and returns 2.
  3. Load the context. `.text` is used as is. `.file(path)` is read as UTF-8. An unreadable file or bad encoding prints a message that names the path and returns 2.
  4. Create `DecisionSession(model:)` and call the runner (wip/wh2). Any error prints the message and returns the code from wip/mfa. Add `UsageError` to that mapping as 2.
  5. Print `outcome.answer` for each outcome, one per line, to stdout. Nothing else goes to stdout.
- `Sources/decide/DecideCommand.swift`: the `@main` type calls `Decide.run` with `CommandLine.arguments.dropFirst()` and `ProcessInfo.processInfo.environment`, then calls `exit` with the result.
- Usage text: one short block that lists `--context`, `--option`, `--help`, the question syntax, and the `DECIDE_MODEL` and `DECIDE_MODEL_API_KEY` variables with the `provider:model` examples from wip/mfa.
- README: change the Setup section to `DECIDE_MODEL=typesafe:jev-latest` and add the `openrouter:typesafe/jev-1.13` form. Leave the `--model` override sentence as it is; the flag is out of scope but the README describes the whole tool.
- `.env` in this repo still has `DECIDE_MODEL=jev-latest`, the old form. It is git-ignored. Change it by hand to `typesafe:jev-latest` and do not commit it.

## Tests

`Tests/DecideCoreTests/DecideRunTests.swift`, Swift Testing. Inject a `ScriptedModel` and capture stdout and stderr in strings:

- The batch example with two choice questions prints two lines in order and returns 0.
- An `@file` context: write a temporary file, then check the request state is `.text` with the file's contents.
- A missing file returns 2, the message names the path, and stdout is empty.
- No arguments returns 2 and the usage text is on stderr.
- `--help` prints the usage text on stdout and returns 0.
- No injected model and no `DECIDE_MODEL` in the environment returns 2 before any request.
- A scripted model that throws `DecisionError.timeout` returns 3, prints a message to stderr, and leaves stdout empty.

`Tests/DecideCoreTests/DecideLiveTests.swift`: a suite whose name contains `DecideLive`. Follow `../DecisionModels/TESTING.md`: the suite reads the real environment, fails (never skips) when `DECIDE_MODEL` or the key is absent, and is left out by name in the normal run:

```sh
swift test --skip DecideLive
set -a; . ./.env; set +a; swift test --filter DecideLive
```

The live test calls `Decide.run` with the real environment, an inline context string (not a file), and the README's team question. It checks the code is 0 and stdout is one of the three option ids followed by a newline.

## Related Issues

Parent: wip/v7x. Blocked on wip/28j, wip/wh2, wip/mfa.

## Acceptance Criteria

- [ ] `swift run decide --context "..." "Question" --option a --option b` prints one line and exits 0 with a valid key.
- [ ] The README batch example, limited to `--option` questions, prints one line per question in order.
- [ ] Usage, configuration, and file errors exit 2. Model runtime errors exit 3. Stdout is empty on every error.
- [ ] `--help` prints the usage text.
- [ ] `swift test --skip DecideLive` passes. `swift test --filter DecideLive` passes with a key.
- [ ] The README Setup section shows the `provider:model` scheme.

---

_📝 Noted on 2026-09-20 18:30:37-04:00 @ git:e31b7ea+local_

Design record (2026-09-20), written before implementation. (1) Signature: 'public static func run(arguments: [String], environment: [String: String], model: (any DecisionModel)? = nil, stdout: inout some TextOutputStream, stderr: inout some TextOutputStream) async -> Int32'. (2) Order inside run: parse (UsageError -> 'Error: <message>' then a blank line then the usage text, all on stderr, return 2; .help -> usage text on stdout, return 0); model = injected model ?? ModelConfiguration(environment:).makeModel() (ConfigurationError -> ExitCode.message on stderr, ExitCode.code); context (.text as is; .file read with String(contentsOfFile:encoding: .utf8); on failure print 'Error: cannot read context file "<path>": <error.localizedDescription>' to stderr and return 2, with no new error type and no usage text); DecisionSession(model:) then Runner.decide (any error -> ExitCode.message on stderr, ExitCode.code); print each outcome.answer with print(_:to: &stdout). Nothing else goes to stdout. (3) ExitCode gains 'case is UsageError: usage' in code(for:) and 'Error: <message>' in message(for:). (4) The process streams: 'Sources/DecideCore/StandardStreams.swift' with 'public struct StandardOutput: TextOutputStream' and 'public struct StandardError: TextOutputStream', each writing through FileHandle (unbuffered, so exit() loses nothing). The @main type stays a few lines. (5) The usage text is 'Decide.usage', a static String, fixed in the worker brief. (6) Tests/DecideCoreTests/DecideCoreTests.swift (the s47 placeholder) is deleted; DecideRunTests replaces it. (7) DecideLiveTests: suite 'DecideLive', .serialized; requires DECIDE_MODEL and DECIDE_MODEL_API_KEY from the process environment; records a failure (never skips) when either is missing; runs the README team question on an inline ticket text and accepts any of the three option ids. (8) README Setup: DECIDE_MODEL=typesafe:jev-latest with the openrouter:typesafe/jev-1.13 form beside it; the --model example value also becomes typesafe:jev-latest, the sentence stays. (9) .env: DECIDE_MODEL changed by hand to typesafe:jev-latest; not committed.
