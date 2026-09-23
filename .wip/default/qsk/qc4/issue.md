---
priority: p2
type: task
created: 2026-09-23T01:04:39-04:00
updated: 2026-09-23T01:25:20-04:00
blocked-on:
  - jt3
may-unblock:
  - rqr
---

# --questions @file: splice a question file's tokens into the command line

# --questions @file: splice a question file's tokens into the command line

## Objective

`decide --context @ticket.txt --questions @triage.txt` runs the three questions in `triage.txt` and prints three answers. The file's tokens take the flag's place in the argument list, so the file's questions sit where the flag was among any command-line questions, `--questions` may repeat, and everything after the splice parses exactly as if typed. A file may hold only questions and their flags. A missing, unreadable, or malformed file exits 10 with a message naming the file, and the line where that applies.

## Context

Part of the `--questions` parent; blocked on the tokenizer sibling (`QuestionFile.tokens(of:path:)`). Decided with the user on 2026-09-23: spliced in place, repeatable, mixing freely with command-line questions. `CommandLineParser.parse` is pure and stays so; the expansion is a separate pure step with an injected reader, the `ConfigFiles.load` pattern from wip/rvj, and `Decide.run` supplies the real reader it already has (`readConfigFile`, which gives nil for no file and a `ConfigReadError` for an unreadable or non-UTF-8 one).

## Location

- `Sources/DecideCore/QuestionFile.swift`: `expanding(_:read:)` beside `tokens`.
- `Sources/DecideCore/CommandLineParser.swift`: the pre-scan predicate becomes a shared internal helper; `--questions` in the main grammar is otherwise unreachable after expansion but keeps a clear error.
- `Sources/DecideCore/Decide.swift`: the expansion before `parse`; the usage text.
- `README.md`: two sentences under the text-file example.
- `Tests/DecideCoreTests/QuestionFileTests.swift`, `DecideRunTests.swift`, `CommandLineParserTests.swift`.

## Approach

**Expansion.** `public static func expanding(_ arguments: [String], read: (String) throws(ConfigReadError) -> String?) throws -> [Item]` on `QuestionFile`, where `public enum Item: Equatable, Sendable { case token(String); case questions([Question]) }`. A command-line argument and every token of a text file become `.token`; `.questions` is for JSON files, which the JSON child issue adds, and this issue never produces it. `CommandLineParser.parse(_ arguments: [String])` stays and becomes a wrapper over a new `public static func parse(items: [Item])`, whose main loop treats a `.questions` item as finished questions appended at that position; a question flag (`--option`, `--level`, `--yes`, `--no`, `--min-confidence`) right after a `.questions` item throws `UsageError("<flag> after --questions belongs to no question")`, and `--quiet`'s one-yes/no-question rule counts them. This issue adds the enum, the wrapper, and the `.questions` handling with a unit test that feeds `parse(items:)` a `.questions` item directly, so the seam is proved before any JSON exists. It returns the arguments unchanged when the line holds `--version`, `--help`, `-h`, or `--set-config`, using the same predicate `parse` uses for its pre-scan (factor it into `CommandLineParser.takesTheLine(_:)`, internal), so help and version still win over a bad file and `--set-config` still reports "runs alone". Otherwise it walks the arguments: `--questions <value>` and `--questions=<value>` (the `flagValue` shape; make that helper internal so this reuses it) are replaced by the value's tokens; every other token passes through. A value `@<path>` reads the file through `read`: nil is `ConfigError(path, 0, "no such file")`; `.unreadable` and `.notUTF8` map as `ConfigFiles.error(_:at:)` does (reuse it). A value with no `@` is the text itself, tokenized with the path `"--questions"` for messages. `@` alone throws `UsageError("--questions @ names no file")`; a missing value is `flagValue`'s `--questions needs a value`. A text whose first token starts with `{` throws `ConfigError(path, line, "JSON question files are not supported yet")`.

Each file's tokens are checked before splicing: the first token may not start with `-` (`ConfigError(path, line, "a question file starts with a question, not a flag")`); every later token that starts with `-` must be `--option`, `--level`, `--yes`, `--no`, or `--min-confidence`, alone or in the `=value` form, else `ConfigError(path, line, "<flag> is not allowed in a question file")`; the token after a bare value flag is its value and is not checked. A file with no tokens contributes nothing. The tokens' texts are spliced in; their lines serve only these messages.

**Parser.** `--questions` reaching `parse` (only when a caller skips expansion, as tests may) throws `--questions needs a value` for a bare flag or, with a value, `UsageError("--questions was not expanded")`; the point is that `parse` never reads a file.

**Run.** In `Decide.run`, before `CommandLineParser.parse`: `let arguments = try QuestionFile.expanding(arguments, read: readConfigFile)`, in the same `do`; a `UsageError` goes through `report` (message and usage) as today's parse errors do, and a `ConfigError` prints `ExitCode.message(for:)` alone and returns 10. The `run` doc comment gains one sentence.

**Usage text**, after the `--context` lines, in the current column:

```
  --questions @<path>            Questions from a file, in the flag's place. The file
                                 holds questions and their flags, split like a command
                                 line; # starts a comment.
  --questions <text>             The same, from the text itself.
```

**README**, after the text-file example's block: "A text question file is split like a command line: whitespace separates tokens, quotes group them, and `#` starts a comment. Its questions take the flag's place, so `--questions` may repeat and mix with questions on the line."

## Tests

- Expansion, in-memory reader: the README line `--context @ticket.txt --questions @triage.txt` expands to the context flag followed by the 14 tokens; a question before and after the flag keeps its place; two `--questions` flags; the `=` form; inline text; unchanged with `--help`, `-h`, `--version`, and `--set-config` even when the file is missing; missing file, unreadable, not UTF-8, JSON, flag-first, and a disallowed `--context`, `--questions`, `-q`, `--model` in a file, each with the message and line; `--option -1` in a file passes (a value is not a flag); an empty file contributes nothing; `--questions @` and a bare `--questions` at the end.
- Parser: `--questions x` unexpanded throws.
- Run level, temp files: the README example with a temp `triage.txt` holding the README's text and `triageModel` gives `returns\nsomewhat_urgent\nyes\n`, exit 0, and the request's questionnaire has three specs in order; a question on the line before the flag answers first; a missing file exits 10, prints nothing on stdout, and reaches no model; a file with `--context` inside exits 10 with the file's line; `--questions @nope --help` prints the usage text and exits 0.
- No live test: a scripted model proves everything here, and the wire does not change (TESTING.md).

## Related Issues

Child of the `--questions` parent; blocked on the tokenizer sibling. Reuses `ConfigFiles.error(_:at:)` (wip/jq1) and `readConfigFile` (wip/rvj). wip/ndr (named contexts) and wip/79i (per-run `--model`) also touch `Decide.run`; land one before starting another.

## Acceptance Criteria

- [ ] The README's `triage.txt` example runs against a scripted model and prints the three answers in order.
- [ ] `--questions` splices in place, repeats, and mixes with command-line questions; help, version, and `--set-config` behave as before even with a bad file on the line.
- [ ] A missing, unreadable, non-UTF-8, JSON, flag-first, or disallowed-flag file exits 10, names the file (and line where one applies), and prints nothing on stdout.
- [ ] `--help` and the README describe the flag and the file format.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-23 01:25:20-04:00 @ git:bb3f1e4+local_

Amended 2026-09-23 while filing JSON question files: the expansion returns items, not strings, so a JSON file's questions can be spliced as finished questions. See the Approach's Expansion paragraph. This issue produces only .token items; the JSON child of the JSON parent produces .questions and is blocked on this issue.
