---
priority: p2
type: task
created: 2026-09-23T01:25:20-04:00
updated: 2026-09-24T00:47:31-04:00
blocked-on:
  - hah
  - qc4
---

# --questions reads a JSON file when it starts with {, and splices its questions in place

# --questions reads a JSON file when it starts with {, and splices its questions in place

## Objective

`decide --context ticket=@ticket.txt --context refund_policy=@refund_policy.txt --questions @triage.json` runs the README's three JSON questions and prints `returns`, `somewhat_urgent`, and `Yes`, each answer on its own line. `--questions` looks at the first non-blank character of what it reads: `{` is a JSON question file, anything else is the text grammar. The JSON file's questions take the flag's place in the question order, as text questions do, and every question name is unique across the run.

## Context

Third child of the JSON question files parent; blocked on the decoder child and on wip/qc4 (the text `--questions`, whose expansion returns `[Item]` with a `.questions` case reserved for this issue). The parent's Design Decisions say why sniffing is safe for questions and why `--context-json` is not built here. The README documents the syntax; wip/ndr builds the named contexts the example uses, so the live test needs it, but the offline tests do not.

## Location

- `Sources/DecideCore/QuestionFile.swift`: the sniff in `expanding`.
- `Sources/DecideCore/CommandLineParser.swift`: the name-uniqueness check.
- `Sources/DecideCore/Decide.swift`: the usage text.
- `Tests/DecideCoreTests/QuestionFileTests.swift`, `CommandLineParserTests.swift`, `DecideRunTests.swift`, `DecideLiveTests.swift`.

## Approach

**Sniff.** In `QuestionFile.expanding`, after a `--questions` value's text is in hand (file or inline), drop a BOM and leading whitespace and look at the first character: `{` gives one `.questions(try questions(fromJSON: text, path: path))` item in the flag's place; `[` throws `ConfigError(path, 0, "a question file is an object with a questions array")`; anything else goes to `tokens(of:path:)` as qc4 built. The "JSON question files are not supported yet" refusal from qc4 goes away.

**Names across the run.** In `parse(items:)`, when a `.questions` item is appended, a name already used by an earlier question on the line throws `UsageError("question name \"team\" is used twice")`; command-line questions have no names, so only JSON files can collide.

**Usage text.** The `--questions @<path>` entry becomes: "Questions from a file, in the flag's place: a JSON file when it starts with {, else questions and their flags split like a command line, # starting a comment." Keep the `--questions <text>` line.

**README.** No change: the JSON example is already there. Its `--json` output example stays a later feature.

## Tests

- Expansion, in-memory reader: `--questions @triage.json` with the README's text yields one `.questions` item holding the three questions, in the flag's place among surrounding tokens; leading whitespace and a BOM before `{` still sniff as JSON; a top-level array throws; a text file is unchanged; an inline `--questions '{"questions": [...]}'` works.
- Parser: two `.questions` items with the same name throw; a `.questions` item followed by `--option` throws the qc4 message; `-q` with one JSON verdict question is allowed.
- Run level, temp files: the README's JSON file with a scripted model answering records keyed `team`, `urgency`, and `refund` (a choice, a rating, and a verdict at 0.87) prints `returns\nsomewhat_urgent\nYes\n`, exit 0, and the recorded request has spec ids `team`, `urgency`, `refund`, instructions of the third an object with the two rules, and the first option's criterion carrying `not_for`, `examples`, and `signals`; a JSON file with a schema error exits 10 naming the file and JSON path with nothing on stdout; a scripted model that reports the refund below 0.7 exits 2 with the unsure message naming question 3 and "Should we issue a refund?".
- Live, one round trip: the README's JSON file with inline named contexts (a refund policy allowing refunds within 30 days, a ticket asking for one five days after delivery), expecting three lines, the first among the three team ids, the second among the three levels, the third `Yes` or `No`, exit 0 or 2. It proves structured instructions and criteria cross the wire through decide's mapping and that the provider accepts them; a scripted model cannot show that. It needs wip/ndr for the named contexts; until then the test may pass one plain `--context` holding both texts.

## Related Issues

Parent: JSON question files. Blocked on the decoder child and wip/qc4. The live test uses wip/ndr's named contexts.

## Acceptance Criteria

- [ ] The README's JSON example runs against a scripted model and prints the three answers, with the request carrying names, rules, and criterion fields.
- [ ] A file starting with `{` is JSON, a text file is unchanged, and a top-level array is refused with its message; a repeated name across the run exits 10.
- [ ] The live test passes with a key.
- [ ] `--help` describes the two file kinds.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-23 01:35:01-04:00 @ git:5da7fb9+local_

Coordination 2026-09-23: the run-wide check that a question name is used once ("question name \"team\" is used twice") lives in CommandLineParser.parse, filed with the --name flag issue byu. Whichever lands first adds it over all finished questions; the other relies on it and tests the JSON case.

---

_📝 Noted on 2026-09-24 00:47:31-04:00 @ git:a5afa16+local_

Coordination (2026-09-24), before start: (1) The decoder is JSONQuestionFile.questions(from:path:) in Sources/DecideCore/JSONQuestionFile.swift (wip/hah's note), not QuestionFile.questions(fromJSON:path:). (2) 'command-line questions have no names' is stale: --name landed (wip/byu), and CommandLineParser.checkUniqueNames runs over every finished question, so a JSON name can collide with a command-line --name or another file; the parser work here is a test of that path through parse(items:), not a new check. (3) Named contexts (wip/ndr) landed, so the live test uses the README's two --context name=... flags. (4) A JSON question's stats and distribution keys arrive as Question.detail and print through PlainOutput (wip/mb3); a run test should pin one JSON question with "distribution": true printing its distribution fields.
