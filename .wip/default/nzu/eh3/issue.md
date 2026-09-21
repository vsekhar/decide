---
priority: p2
type: task
created: 2026-09-20T20:34:00-04:00
updated: 2026-09-20T21:06:37-04:00
may-unblock:
  - h9x
  - xhd
---

# Add --level questions: a rating answered with the chosen level id

## Objective

A question followed by `--level` flags becomes a rating: the model places the context on the ordered scale the levels define, and the tool prints the id of the most likely level. The README's Leveling section works, alone and in a batch beside `--option` questions.

## Context

Part of wip/nzu. The skeleton (wip/v7x) knows one question kind, a choice from `--option` values. The README's Leveling section adds:

```sh
decide --context @ticket.txt "How urgent is this ticket?" --level not_urgent --level somewhat_urgent --level urgent
decide --context @ticket.txt "How urgent is this ticket?" --level not_urgent="Customer feedback or feature request" --level somewhat_urgent="Customer problem, but customer not blocked" --level urgent="Customer blocked"
```

Library facts, paths relative to `../DecisionModels` (the package depends on tag 0.1.0):

- `QuestionSpec.Kind.rating(levels: [Criterion])`: levels carry no id on the wire, only a criterion, in order low to high (`Sources/DecisionModels/QuestionSpec.swift`). The CLI maps indices back to ids.
- `AnswerRecord.rating(score: Double, probabilities: [Int: Double], confidence: Double?)`: probabilities keyed by level index; `record.confidence` gives the reported value or the library's formula (`Sources/DecisionModels/AnswerRecord.swift`).
- The library's `Rating.value` picks the most likely level and breaks a tie toward the lower level, not `round(score)` (`Sources/DecisionModels/Rating.swift`). `AnswerReader.rating` treats an index outside the scale as `malformedResponse` and an absent index as probability zero (`Sources/DecisionModels/AnswerReader.swift`).
- `Preflight` rejects a rating with fewer than two levels as `invalidQuestion`; Jev allows at most 10 levels (`unsupported(.tooManyLevels)`), which `ExitCode` already maps.

## Design

- `Question` loses `options` and gains `kind`: `public enum Kind: Sendable, Equatable { case choice([Option]); case rating([Option]) }`. A level has the same two fields as an option (id, optional description), so the `Option` struct serves both; say so in its doc comment. wip/h9x adds a `.verdict` case.
- Grammar: the first kind flag after a question fixes its kind. `--option` makes a choice, `--level` makes a rating. (After wip/h9x a question with neither is a verdict, and wip/xhd adds `--min-confidence` as a modifier on every kind; neither is part of this issue.) A flag of the other kind on the same question is a usage error that names the question, for example `question 2 ("How urgent is this ticket?") mixes --option and --level`. `--level VALUE` and `--level=VALUE` both work; `id=description` splits at the first `=`, an empty description counts as none, an empty id is an error, all as `--option` does today.
- After the walk: a question with no kind flag is an error, now worded `has no --option or --level` (wip/h9x removes this error: a bare question becomes a verdict); a rating with one level is an error, `question N ("...") needs at least two --level`; a repeated level id is an error like the repeated option id.
- Runner: a rating question becomes `QuestionSpec(id:, instructions: .text, kind: .rating(levels: levels.map { Criterion($0.description ?? $0.id) }))`. Reading the answer: a `.rating` record is required, else `malformedResponse("The answer for qN is not a rating.")`; an index outside `0..<levels.count` is `malformedResponse` naming the question; the printed answer is the level with the highest probability, ties to the lower index; `Outcome.probabilities` is keyed by level id with absent levels at 0; `Outcome.confidence` is `record.confidence`. A choice question keeps its current path, and a `.rating` record under a choice question stays a malformed response.
- `Decide.usage` gains `--level <id>` and `--level <id>=<text>` lines beside the `--option` lines, and the first paragraph says the answer is the chosen option or level.
- `Examples/ticket.sh` gains the README's urgency question with the three described levels as a second question in the same run. Expected answer: somewhat_urgent.

## Location

- `Sources/DecideCore/Invocation.swift`: `Question.kind`, `Question.Kind`.
- `Sources/DecideCore/CommandLineParser.swift`: `--level`, the kind rule, the new messages.
- `Sources/DecideCore/Runner.swift`: the rating spec and the rating read.
- `Sources/DecideCore/Decide.swift`: the usage text.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `RunnerTests.swift`, `DecideRunTests.swift`: additions; existing tests change only where `Question(instructions:options:)` becomes `Question(instructions:kind:)`.
- `Examples/ticket.sh`.

## Tests

Swift Testing, `ScriptedModel`, no network:

- Parser: the two README leveling lines parse to one `.rating` question with three levels, bare and described; `--level=id` works; a question with `--option` then `--level` throws and the message names the question; one level throws; repeated level ids throw; a question with no kind flag throws with the new wording; the batch example with a choice question then a rating question parses to two questions with the right kinds.
- Runner: the spec for a rating carries `.rating(levels:)` with criterion summaries in order, a bare level's summary is its id; a record `.rating(score: 1.2, probabilities: [0: 0.15, 1: 0.55, 2: 0.30], confidence: 0.78)` gives answer `somewhat_urgent`, confidence 0.78, probabilities keyed by id; a tie between indices 0 and 2 gives the lower level; an index of 3 on a three-level scale throws `malformedResponse` naming the question; a `.choice` record under a rating question throws `malformedResponse`; a choice question and a rating question in one call make one request.
- Run: `--context "..." "Which team handles this ticket?" --option ... "How urgent is this ticket?" --level ...` prints two lines in order and returns 0.

## Related Issues

Parent: wip/nzu. wip/h9x builds on the `Kind` enum this issue adds. wip/28j, wip/wh2, wip/ayd hold the design notes of the code this changes.

## Acceptance Criteria

- [ ] The README's two leveling commands print one level id and exit 0 against the real model (check by hand with `Examples/ticket.sh`).
- [ ] A batch with an `--option` question and a `--level` question prints one line per question, in order, from one request.
- [ ] Mixed kinds on one question, fewer than two levels, and repeated level ids each exit 2 with a message that names the question.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean and `swift test --skip DecideLive` passes.
