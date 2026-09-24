---
priority: p2
type: feature
created: 2026-09-24T02:31:41-04:00
updated: 2026-09-24T02:31:41-04:00
---

# Read a context or a question file from standard input with -

## Objective

`-` as a value means standard input. `cat ticket.txt | decide --context ticket=- "Which team handles this ticket?" --option shipping --option billing --option returns` reads the whole of stdin as the context named `ticket` and prints the answer. `cat triage.txt | decide --context @ticket.txt --questions -` reads a question file from stdin and splices its questions in the flag's place, as `--questions @triage.txt` does. Every form takes it: `--context -`, `--context=-`, `--context <name>=-`, `--context=<name>=-`, `--questions -`, and `--questions=-`. Standard input reads once per run, so a line with `-` in two places is a usage error, whichever two flags hold them. `@-` still names a file called `-`, and `-x` is still text.

## Context

Requested by the user on 2026-09-24. The README's Streaming section already writes `--context-json event=-` for the future `--each` mode, so `-` for stdin is the convention the spec has picked; this issue gives `-` its whole-input meaning now, and `--each` will later read it line by line. Today `--context -` is the text `-`, `--questions -` fails with `a question file starts with a question, not a flag`, and a bare `-` as a question is `unknown flag: -` (`CommandLineParserTests.unknownFlag`); none of that is worth keeping, so no behavior anyone relies on changes.

How the code stands:

- `ContextSource` (`Invocation.swift`) is `.text(String)` or `.file(String)`. `CommandLineParser.contextSource(from:as:)` makes one from a value: `@` prefix is a file, anything else is text. `contextEntry(from:)` splits a name off the first `=` and calls it for the rest. `context(from:)` checks the line's values together: the mix rule first, then repeated names.
- `QuestionFile.expanding(_:read:)` runs before the parser. It replaces each `--questions` value with the file's tokens, or one `.questions` item for a JSON file, through `source(of:read:)`: `@path` reads through the injected `read` closure, anything else is inline text whose messages name `--questions`. `ConfigFiles.error(_:at:)` maps a `ConfigReadError` (`.unreadable`, `.notUTF8`) to a `ConfigError` at the path. A line with `--help`, `-h`, `--version`, or `--set-config` comes back as it is and reads nothing (`CommandLineParser.takesTheLine`).
- `Decide.run` expands, parses, loads config, makes the model, then `loadState` reads each context: `loadContext` returns the text or reads the file with `String(contentsOfFile:)`, printing `Error: cannot read context file "<path>": <reason>` and exiting 10 when it fails. So a bad model setting fails before any context file is read; keep that order for stdin.
- `Decide.run` takes `model:` as an injected double and `stdout`/`stderr` as `String` streams in tests; there is no stdin seam yet. `StandardStreams.swift` holds `StandardOutput` and `StandardError`.
- Messages about a question file hold the path and the line, never the file's text; a stdin file must keep that rule.

## Location

- `Sources/DecideCore/Invocation.swift`: `ContextSource.standardInput`.
- `Sources/DecideCore/CommandLineParser.swift`: `contextSource(from:as:)`, `context(from:)`, the `parse` doc comment.
- `Sources/DecideCore/QuestionFile.swift`: `expanding(_:read:standardInput:)`, `source(of:read:standardInput:)`.
- `Sources/DecideCore/StandardStreams.swift`: `StandardInput`.
- `Sources/DecideCore/Decide.swift`: the `run` signature, the once-per-run check, `loadContext`, the usage text.
- `README.md`: one short example block; `DEVELOPMENT.md`: the one-line description of `StandardStreams.swift`.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `QuestionFileTests.swift`, `DecideRunTests.swift`.

## Approach

**Type.** `ContextSource` gains `case standardInput`, documented as "the whole of standard input, from `--context -` or `--context <name>=-`; the run reads it as UTF-8". Update the `Invocation` doc comment, which says only `.file` names something the run reads.

**Parser.** In `contextSource(from:as:)`, a value equal to `-` is `.standardInput`, checked before the `@` rule so `@-` stays `.file("-")`. `-x` and ` -` are text as now. In `context(from:)`, after the mix and repeated-name checks, count sources that are `.standardInput`; two or more throw the once-per-run error. Use one message everywhere it fires, a static string on `CommandLineParser` so the expansion and the run print the same words, something like `- was given twice: standard input reads once`. Keep the check order: a line with `--context -` and `--context b=-` reports the mix rule first, as an unnamed value among named ones does today.

**Expansion.** `expanding` gains a third parameter, `standardInput: () throws(ConfigReadError) -> String`, non-escaping like `read`. In `source(of:read:standardInput:)`, a value equal to `-` reads through it and names the path `stdin` in every message, so a bad file prints `Error: stdin:3: unterminated quote` or `Error: stdin: questions[0]: missing key "instructions"`. Map `.unreadable` to `ConfigError(path: "stdin", line: 0, problem: "cannot read standard input")` rather than `cannot read the file`; `.notUTF8` can go through `ConfigFiles.error(_:at:)` as it is. A local flag records that stdin was read; a second `-` throws the once-per-run `UsageError` instead of reading again. The JSON sniff, the text rules, and the empty-file rule apply to stdin as they do to a file: empty stdin contributes no questions. The `takesTheLine` guard already keeps `--help` from reading; a test proves the closure is never called then. Accept that with `--questions - --questions -` the first `-` reads stdin before the second is seen: on a pipe nothing is lost, and a pre-scan of the line would duplicate the flag grammar for a case nobody hits.

**Standard input.** Add `public struct StandardInput` to `StandardStreams.swift` beside the two output streams, with `public func readToEnd() throws(ConfigReadError) -> String`. Use `FileHandle.standardInput.readToEnd()`, the throwing one, not `readDataToEndOfFile()`, which raises an uncatchable exception on macOS when the descriptor is closed (`decide ... <&-`); a throw is `.unreadable`, nil is the empty string, and bytes that are not UTF-8 are `.notUTF8`, decoded by hand as `readConfigFile` does so Linux and macOS give the same words. It reads to EOF, so `-` on a terminal waits for Ctrl-D, as `cat -` does; no TTY detection.

**Run.** `Decide.run` gains `standardInput: () throws(ConfigReadError) -> String` with the process's stdin as the default, so `DecideCommand` needs no change and tests pass a closure over a string, the way they pass `model:`. Inside `run`, wrap it in a closure that sets a local `var` when called, pass the wrapper to `expanding`, and right after `parse`, in the same `do`, throw the once-per-run `UsageError` when that flag is set and the invocation holds a `.standardInput` source (a small computed property on `Context`, or a loop in `run`). That error goes through `report`, message plus usage, exit 10, before config files, the model, or any context load. `loadContext` gets a `.standardInput` case that reads through the wrapper and prints `Error: cannot read standard input` or `Error: standard input is not valid UTF-8`, exit 10, no model call; it runs after `makeModel`, so a bad `--model` still fails first. The `run` doc comment gains one sentence.

**Usage text.** In the current column, after `--context @<path>`: `--context -   Context from standard input.`; after `--context <name>=@<path>`: `--context <name>=-   A named context from standard input.`; after `--questions <text>`: `--questions -   The same, from standard input.` and a wrapped second line: `- may appear once on a line: standard input reads once.` `DecideRunTests` asserts exact usage blocks (`usageListsTheDetailFlags`, "--help lists --questions and both file kinds", and others); update the expected text there.

**README.** One block under Advanced usage, before Statistics, titled "Standard input":

```sh
# - reads the whole of standard input as a context or as a question file, once per run
$ cat ticket.txt | decide --context ticket=- --questions @triage.txt
$ cat triage.txt | decide --context @ticket.txt --questions -
```

One sentence after it: a run reads standard input once, so `-` may appear once on a line, and `@-` names a file called `-`. Leave the Streaming section as it is; `--each` is not this issue.

**DEVELOPMENT.md.** The layout line for `StandardStreams.swift` says stdout and stderr; make it the three process streams.

## Out of Scope

- `--each` and `--context-json`: line-by-line reading and JSON contexts from the Streaming section. This issue reads stdin whole, once.
- Detecting a terminal on stdin, or a timeout: `-` waits for EOF.
- A default of stdin when the line has no `--context`: a bare question still runs with no state.
- Any library change; `State` and `DecisionSession` are untouched.

## Tests

- Parser (`CommandLineParserTests`): `--context -` and `--context=-` give `.single(.standardInput)`; `--context ticket=-` and `--context=ticket=-` give `.named([NamedContext(name: "ticket", source: .standardInput)])`; `--context a=- --context b=-` throws the once-per-run message; `--context @-` gives `.file("-")` and `--context ticket=@-` its named twin; `--context -x` and `--context ticket=-x` are text; `--context - --context b=@f` reports the mix rule; a bare `-` question is still `unknown flag: -`; `--option -` is still an option id.
- Expansion (`QuestionFileTests`, through the `expand` helper with a stdin closure and a call counter): `--questions -` and `--questions=-` with the README's `triage.txt` text give its 15 tokens in place, and with `triage.json` one `.questions` item of its three questions; an unterminated quote names `stdin:<line>`; a JSON fault names `stdin` and the JSON path; `.unreadable` gives `stdin: cannot read standard input` and `.notUTF8` gives `stdin: is not valid UTF-8`; empty stdin contributes nothing; two `-` throw the usage error and the closure ran once; `--questions - --help` never calls the closure; `@-` reads the file `-` through `read`, not stdin.
- Run (`DecideRunTests`, scripted model): `--context ticket=-` with the ticket text on the injected stdin sends `.object(["ticket": .text(text)])` and prints `returns`, exit 0; `--context -` sends `.text(text)`; `--questions -` with the README's `triage.txt` text prints the three answers in order; `--questions -` plus `--context ticket=-` exits 10 with the once-per-run message and the usage text on stderr, nothing on stdout, no model call, and the closure ran at most once; a closure that throws `.unreadable` under `--context ticket=-` exits 10 with `Error: cannot read standard input`, no model call; `.notUTF8` likewise; a bad `--model` with `--context ticket=-` exits 10 without calling the closure; the `--help` block tests updated.
- No live test: the wire does not change and a scripted model proves everything (TESTING.md). Linux CI must stay green; `FileHandle.readToEnd()` exists in swift-corelibs-foundation, and no message carries Foundation's own text.

## Related Issues

- wip/ndr: named contexts and `ContextSource`; this issue adds the third case.
- wip/qc4 and wip/rqr: the expansion and its injected reader; this issue adds a second reader beside it.
- wip/5gr: a run with no context stays as it is.

## Acceptance Criteria

- [ ] `--context -`, `--context <name>=-`, and `--questions -` (and the `=` forms) read the whole of standard input, and the README's two examples run against a scripted model.
- [ ] A line with `-` in two places, across any two of the three flags, exits 10 with one message and the usage text, reads no more than once, and reaches no model.
- [ ] `@-` names a file called `-`; `-x` is text; a bare `-` question and `--option -` behave as before.
- [ ] A stdin that does not read or is not UTF-8 exits 10 with a message naming standard input, for both the context and the questions case, with no Foundation text in it.
- [ ] `--help` and the README describe `-`, and every usage-text test passes.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.
