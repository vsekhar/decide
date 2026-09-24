---
priority: p2
type: task
created: 2026-09-23T01:25:20-04:00
updated: 2026-09-23T04:12:17-04:00
may-unblock:
  - hah
  - byu
---

# Questions carry a name, rules, and rich criteria, and the questionnaire sends them

# Questions carry a name, rules, and rich criteria, and the questionnaire sends them

## Objective

`Question` and `Option` in `DecideCore` can hold everything the README's JSON question file expresses: a question name, structured instructions (a question plus rules), and criteria with `not_for`, `examples`, and `signals`. `Runner.makeQuestionnaire` sends each of these to the library in the form it defines, and a named question runs under its name. Every existing construction site compiles unchanged, and the command line's questions produce exactly the questionnaire they do today.

## Context

First child of the JSON question files parent, whose Design Decisions section is the record. The library types this maps to: `Criterion(summary, notFor:, examples:, signals:)` (`DecisionModels/Criterion.swift`); `QuestionSpec.instructions: State`, a JSON value, so structured instructions are `.object(["question": .text(q), "rules": .array([...])])` (`QuestionSpec.swift`); `QuestionSpec.id`, which must be unique per request (`Preflight.swift:15`). The library's preflight refuses structured criteria and structured instructions for a provider whose capabilities lack them, throwing `DecisionError.unsupported`, which `ExitCode` already maps to exit 10 with "the model cannot take this request: structured criteria" or "structured instructions"; nothing here needs to check capabilities.

Today (`Sources/DecideCore/Invocation.swift`, `Runner.swift`): `Question` has `instructions: String`, `kind`, `minimumConfidence`; `Option` has `id` and `description`; `makeQuestionnaire` uses `q<N>` ids and `Criterion(description ?? id)`; `Runner.decide` looks answers up by `identifier(at:)`.

## Location

- `Sources/DecideCore/Invocation.swift`: fields on `Question` and `Option`.
- `Sources/DecideCore/Runner.swift`: `makeQuestionnaire`, `identifier`.
- `Tests/DecideCoreTests/RunnerTests.swift`.

## Approach

**Question.** Add `public var name: String?` ("The question's name from a JSON file, which is the id it runs under and the key `--json` output will use; nil for a command-line question, which runs as `q<N>`") and `public var rules: [String]` ("Rules the model applies with the question, from a JSON file's structured instructions; empty for a plain question"). The initializer gains `name: String? = nil` and `rules: [String] = []` after `minimumConfidence`, so every call site compiles unchanged. `instructions` stays a `String`: for a structured question it is the `question` text, which the unsure message and the usage of `instructions` elsewhere keep working.

**Option.** Add `public var notFor: String?`, `public var examples: [String]`, `public var signals: [String]`, with doc comments naming the JSON keys (`not_for`, `examples`, `signals`), and initializer defaults `nil`, `[]`, `[]` after `description`.

**Runner.** `makeQuestionnaire`: the spec id is `question.name ?? "q\(index + 1)"`; a private `identifier(for question: Question, at index: Int)` replaces `identifier(at:)` and `decide` uses the same function, so lookups match. Instructions: `rules.isEmpty ? .text(instructions) : .object(["question": .text(instructions), "rules": .array(rules.map { .text($0) })])`. Every `Criterion` is built as `Criterion(description ?? id, notFor: notFor, examples: examples, signals: signals)` for options and levels; for a verdict side, a side with no description and no other field sends no criterion (as today), and a side with any field sends `Criterion(description ?? id, ...)`. `Outcome.questionID` carries the spec id, so it is the name for a named question. Doc comments on `makeQuestionnaire` gain a sentence on names and one on rules.

## Tests

`RunnerTests`: a named question's spec id is its name and the unnamed one beside it is `q2` (numbering counts positions, not unnamed questions); `decide` reads a named answer back under the name; rules become the object instructions, exactly `{"question": ..., "rules": [...]}` as `State`; an option with `notFor`, `examples`, and `signals` becomes a `Criterion` with those fields; a level and a verdict side likewise; a verdict side with only `examples` and no description sends `Criterion(id, examples:)`; the existing tests are unchanged and prove the defaults.

## Related Issues

Parent: JSON question files. The JSON decoder child is blocked on this issue. wip/ndr (named contexts) also changes `Runner.decide`'s signature; land one before starting the other.

## Acceptance Criteria

- [ ] `Question` and `Option` hold name, rules, `notFor`, `examples`, and `signals`, with defaults, and every existing test passes unchanged.
- [ ] `makeQuestionnaire` sends names as ids, rules as object instructions, and the criterion fields, all pinned by tests; `Runner.decide` reads a named answer back.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean and `swift test --skip DecideLive` passes.

---

_📝 Noted on 2026-09-23 03:58:30-04:00 @ git:40ae06a+local_

Design record (2026-09-23), the decisions the Approach left open. Implemented as written there, plus:
1. Two private helpers in Runner build criteria: criterion(_ option: Option) -> Criterion always builds Criterion(description ?? id, notFor:, examples:, signals:), for options and levels; sideCriterion(_ side: Option) -> Criterion? returns nil when the side has no description, no notFor, no examples, and no signals, else criterion(side). So a bare --yes or --no label still sends no criterion, as today.
2. identifier(for:at:) is `question.name ?? "q\(index + 1)"`; N is the position in the run, so a named question does not shift its neighbours' numbers. Both makeQuestionnaire and decide call it.
3. Question.name's doc does not say where the name comes from (wip/byu and wip/hah each add a source); it says what the name is for.
4. The instructions object is built as State: .object(["question": .text(instructions), "rules": .array(rules.map(State.text))]).
5. Existing tests are untouched; they prove the defaults. New RunnerTests build questions with the new fields directly.
6. wip/ndr landed first, so Runner.decide already takes State?; nothing to reconcile.

---

_📝 Noted on 2026-09-23 04:03:11-04:00 @ git:40ae06a+local_

Implementation (2026-09-23): a worker implemented the Approach and the design record as written; no open question came up. Beyond the record:
- The instructions State is built into a local before the QuestionSpec call, for width.
- Both inits are one parameter per line now, as Invocation.init already is.
- Tests 1 and 2 share a static namedQuestions helper (the team question named "team" and the unnamed urgency question); test 4 checks the rich shipping option and the bare billing option from one questionnaire.
- Outcome.questionID's doc now says "its name, or q1, q2, and so on for an unnamed question"; the worker flagged it and I changed it.
Checks: warnings-as-errors build clean; `swift test --skip DecideLive` 288 tests in 8 suites pass; no existing test changed.

---

_📝 Noted on 2026-09-23 04:12:17-04:00 @ git:40ae06a+local_

Summary (2026-09-23): done. Question has name and rules; Option has notFor, examples, and signals; makeQuestionnaire sends the name as the spec id (q<N> by position otherwise), rules as {"question", "rules"} object instructions, and every criterion field; decide looks answers up by the same id. Today's command lines produce a byte-identical questionnaire (the verifier dumped 15 lines against HEAD in a scratch copy).
Verifier: all three acceptance criteria hold, no blockers; a live probe with rules and full criteria was accepted by the real model, the named answer came back under its name. Acted on one note: verdictSideCriterion now also pins a notFor-only and a signals-only side, and a mutant on either guard term fails it. Notes for the name sources (wip/byu, wip/hah): the unsure message still says "question N", by position, as byu's Approach intends; a name equal to a positional id (naming question 1 "q2" beside an unnamed question 2) is caught by the library's preflight, exit 10 "invalid question q2: Two questions share the id."; --show-names already prints a name, so byu adds that test.
Final: warnings-as-errors build clean; `swift test` with .env sourced, 292 tests in 9 suites passed, live included.
