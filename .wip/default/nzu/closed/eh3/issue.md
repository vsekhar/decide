---
priority: p2
type: task
created: 2026-09-20T20:34:00-04:00
updated: 2026-09-20T22:34:03-04:00
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

---

_📝 Noted on 2026-09-20 22:16:03-04:00 @ git:5efc7eb+local_

Design record, 2026-09-20 session. Corrections to the issue text: usage errors now exit 10 (ExitCode.setup), not 2, since wip/fjj landed first; read 'exit 2' in the acceptance criteria as 10. Decisions that fix the implementation: (1) Question.init(instructions:kind:) with no default for kind; Question.options is gone with no alias. Kind is 'public enum Kind: Sendable, Equatable { case choice([Option]); case rating([Option]) }'. (2) Parser messages, exact: 'a --level has no id'; 'question N ("...") mixes --option and --level' with the question's existing kind flag named first and the offending flag second (so --level then --option reads 'mixes --level and --option'); 'question N ("...") has no --option or --level'; 'question N ("...") needs at least two --level'; 'question N ("...") repeats the level "x"'; '--level before any question'; '--level needs a value'. (3) Runner: rating spec is .rating(levels: levels.map { Criterion(/bin/zsh.description ?? /bin/zsh.id) }); the answer is the level whose index has the highest probability, scanning indices 0..<count with strict greater-than so ties go to the lower index and an all-absent record picks level 0; an index outside the range throws malformedResponse 'The answer for qN names level I, but the question has C levels.'; a non-rating record under a rating question throws 'The answer for qN is not a rating.'; probabilities keyed by level id, absent levels 0; confidence is record.confidence; the score field is unused. (4) Usage line becomes 'Usage: decide --context <text> "<question>" (--option <id>... | --level <id>...) ["<question>" ...]...'; paragraph says 'the id of the chosen option or level'; two --level lines beside the --option lines. (5) Examples/ticket.sh gains the README's described urgency levels as a second question in the same run. Implementation delegated to a worker; the brief holds the prose verbatim.

---

_📝 Noted on 2026-09-20 22:24:47-04:00 @ git:5efc7eb+local_

Worker done; diff read in the main context. Shape: CommandLineParser keeps a private QuestionBuilder (instructions, first kind flag, values) and a private KindFlag enum (rawValue is the flag text, plus a noun for the repeat message and the has-no-id sentence); add(_:as:to:) applies the first-flag-fixes-kind rule and the mixed-kinds message before splitting the value; builder.question(number:) checks no-flag, then repeats, then the two-level minimum. Runner.makeQuestionnaire switches on kind inside the existing map; Runner.decide switches on the question's kind and a private ratingOutcome does the index check (ascending, first offender), the strict-greater scan from index 0, and the id-keyed probabilities. Tests 57 -> 70 in 5 suites, build clean with warnings as errors. Live check by hand: Examples/ticket.sh with the described levels printed 'returns' then 'urgent' and exited 0, one request; the issue guessed somewhat_urgent, but the ticket says the customer is stuck until the return clears, so 'urgent' is a fair reading and the criterion (one level id, exit 0) holds.

---

_📝 Noted on 2026-09-20 22:34:03-04:00 @ git:5efc7eb+local_

Verifier: all four acceptance criteria hold, no blockers, no should-fixes, seven notes. Acted on: (1) design change, logged here as the record: the library's AnswerRecord.confidence infers the level count from the record (max index + 1) and the option count from the record's keys, so a record that leaves out a level or option understates confidence (probe: [0: 0.7, 1: 0.3] on a three-level scale gave 0.08 alone, 0.54 over all three). Runner.decide now fills every absent level or option with 0 before asking the library, so Outcome.confidence is the section 6.1 number over the whole scale, and Outcome.probabilities for a choice also carries absent options at 0. The reported confidence still wins when the provider gives one. This matters for wip/xhd, which gates on this number. (2) Tests pin the numbers: 0.3462 for the full three-level record with nil confidence, 0.5417 for the omitted-level case, 0.4439 for a two-of-three choice record; both omitted-case tests fail with the fill removed (mutant proven) and pass restored. (3) Added the two parser tests the note named (--level as the last token; --level a= counts as no description) and a rating-under-choice runner test. (4) Reworded three doc comments that used 'the walk' as a noun. Not acted on: levels[best] would trap on an empty level list, unreachable because the parser and the library's Preflight both refuse fewer than two levels; the library caps a rating at 10 levels with a clear message and no CLI test covers that. Live, by hand: the bare form 'How urgent is this ticket?' --level not_urgent --level somewhat_urgent --level urgent on Examples/ticket.txt printed somewhat_urgent and exited 0, so both README leveling commands are checked. Final: 75 tests in 5 suites, build clean with warnings as errors. Summary: --level questions parse as ratings, go on the wire as ordered criteria, and print the most likely level's id; confidence is computed over the whole scale.
