---
priority: p2
type: task
created: 2026-09-20T18:12:56-04:00
updated: 2026-09-20T18:26:04-04:00
blocked-on:
  - s47
may-unblock:
  - ayd
---

# Build the questionnaire and run all questions in one request

## Objective

Turn the parsed questions into a DecisionModels `Questionnaire`, send them with the context in one request through a `DecisionSession`, and return the answers in question order as plain values: answer id, confidence, and the probabilities.

## Context

Part of wip/v7x. The README's Batch questions section promises one request per context, however many questions. The library does this natively: a `Questionnaire` with N specs is one `DecisionRequest`.

Use the wire-level types, not `Choose<Option>`. The library has no `ChoiceOption` conformance for `String`, and the CLI only needs string ids back. Library facts, with paths relative to `../DecisionModels`:

- `Questionnaire(_ specs: [QuestionSpec] = [])`: `Sources/DecisionModels/Questionnaire.swift:5`.
- `QuestionSpec(id:instructions:kind:)`, `Kind.choice(options: [OptionSpec])`, `OptionSpec(id:criterion:)`: `Sources/DecisionModels/QuestionSpec.swift`.
- `Criterion(_ summary: String, notFor:examples:signals:)`, also `ExpressibleByStringLiteral`: `Sources/DecisionModels/Criterion.swift:16`.
- `DecisionSession.decide(_ questionnaire: Questionnaire, about state: some StateRepresentable, options:) async throws -> Answers`: `Sources/DecisionModels/DecisionSession.swift:154`. `String` conforms to `StateRepresentable`, so pass the context string as is. There is no `respond` variant for a questionnaire, so usage and request id are not available on this path. The skeleton does not need them.
- `Answers.records: [String: AnswerRecord]` and `AnswerRecord.choice(reported: String, probabilities: [String: Double], confidence: Double?)`. `AnswerRecord.confidence` returns the reported value or the library's formula: `Sources/DecisionModels/AnswerRecord.swift`.
- Before it sends, the session throws `DecisionError.invalidQuestion` for an empty questionnaire, duplicate question ids, a choice with no options, or duplicate option ids.

## Approach

- `Sources/DecideCore/Runner.swift`:
  - `func makeQuestionnaire(_ questions: [Question]) -> Questionnaire`. Ids are `q1`, `q2`, ... in order. Instructions are `.text(question.instructions)`. Each option becomes `OptionSpec(id: option.id, criterion: Criterion(option.description ?? option.id))`. A bare option uses its id as the summary, because `Criterion` needs a summary and the id is what the model sees either way.
  - `struct Outcome { let questionID: String; let answer: String; let confidence: Double; let probabilities: [String: Double] }`. Do not name it `Decision`, `Answer`, or `Verdict`; those are library types.
  - `func decide(_ questions: [Question], about context: String, using session: DecisionSession) async throws -> [Outcome]`. Build the questionnaire, call `session.decide(questionnaire, about: context)`, then read `answers.records["q\(i)"]` for each question in order. A missing record, or a record that is not `.choice`, throws `DecisionError.malformedResponse` with the question id in the message. wip/mfa maps that case to exit code 3.
- `Question` and `Option` live in `Sources/DecideCore/Invocation.swift`, owned by wip/28j. If this issue lands first, create that file with those two structs (`Question`: `instructions: String`, `options: [Option]`; `Option`: `id: String`, `description: String?`) and wip/28j adds the rest.

## Tests

`Tests/DecideCoreTests/RunnerTests.swift`, Swift Testing, with `ScriptedModel` from `DecisionModelsTesting` (`../DecisionModels/Sources/DecisionModelsTesting/ScriptedModel.swift`). The closure form receives the `DecisionRequest`, so a test can inspect the questionnaire and the state and return `Answers(records:quality:)`. `callCount` reports the number of requests.

- Questionnaire shape: ids `q1`...`qN`, instructions as given, option ids as given, a description becomes the criterion summary, a bare option's summary is its id.
- Two questions produce one request (`callCount == 1`). The request carries both specs and the context as `.text`.
- Outcomes come back in question order with the reported id, confidence, and probabilities.
- A missing record throws `DecisionError.malformedResponse`.
- A record of the wrong kind (for example `.verdict`) throws `DecisionError.malformedResponse`.

## Related Issues

Parent: wip/v7x. Blocked on wip/s47. Shares `Invocation.swift` with wip/28j. wip/ayd calls `decide(_:about:using:)`.

## Acceptance Criteria

- [ ] N questions produce one `DecisionRequest`.
- [ ] Outcomes are in question order with answer, confidence, and probabilities.
- [ ] Option descriptions reach the request as the criterion summary. A bare option uses its id.
- [ ] Tests pass with `ScriptedModel` and no network.

---

_📝 Noted on 2026-09-20 18:26:04-04:00 @ git:ccab071+local_

Design record (2026-09-20). Question and Option come from Sources/DecideCore/Invocation.swift, written and committed by the main session; this issue does not edit that file. Decisions beyond the issue text: (1) The two functions are static members of 'enum Runner' (Runner.makeQuestionnaire(_:) and Runner.decide(_:about:using:)), not free functions, so they read clearly next to Decide.run and DecisionSession.decide. (2) Outcome is 'public struct Outcome: Sendable, Equatable'. (3) In test files that import both DecideCore and DecisionModels, 'Question' is ambiguous (the library has a protocol of that name); tests write DecideCore.Question. Inside DecideCore the module's own type shadows the import. (4) malformedResponse messages: 'The response holds no answer for q2.' and 'The answer for q2 is not a choice.' Implemented by a worker in a scratch worktree, then copied back.
