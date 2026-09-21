---
priority: p2
type: task
created: 2026-09-20T20:34:09-04:00
updated: 2026-09-20T22:56:49-04:00
blocked-on:
  - eh3
may-unblock:
  - xhd
---

# Add --yes and --no: a bare question is a verdict answered with the yes or no value

## Objective

A question with no `--option` and no `--level` is a yes/no question, the simplest kind. The model gives the probability that the answer is yes; the tool prints the yes value when that probability is at least 0.5 and the no value otherwise. `--yes` and `--no` set the two values and, with `=description`, what each side means. The README's Yes or no section, without its `--min-confidence` flag (wip/xhd adds that), works on one context, alone and in a batch beside `--option` and `--level` questions.

## Context

Part of wip/nzu. Blocked on wip/eh3, which introduces `Question.Kind`. Decided with the user on 2026-09-20: a bare question is a verdict, `--yes` and `--no` only decorate one, and the confidence bar is a separate feature (wip/xhd) that applies to every kind. The README's lines, minus the bar:

```sh
decide --context @ticket.txt "Should we issue a refund?" --yes "Hell yeah" --no "Forget it"
decide --context @ticket.txt "Should we issue a refund?" --yes Yes --no No     # the batch example's third question
decide --context "$body" "Is this message spam?"                                # a bare question prints yes or no
```

The README's composite-context refund example (`--context ticket=@ticket.txt --context refund_policy=@refund_policy.txt`) needs named contexts, which stay out of scope; the question runs on the ticket alone.

Library facts, paths relative to `../DecisionModels` (tag 0.1.0):

- `QuestionSpec.Kind.verdict(ifTrue: Criterion?, ifFalse: Criterion?)`: both criteria are optional (`Sources/DecisionModels/QuestionSpec.swift`).
- `AnswerRecord.verdict(probability: Double)` is P(yes); `record.confidence` is `abs(2p - 1)`, the DESIGN.md section 6.1 formula (`Sources/DecisionModels/AnswerRecord.swift`, `ConfidenceMath.swift`). `Verdict.value` is `probability >= 0.5` (`Sources/DecisionModels/Verdict.swift`). `AnswerReader.verdict` rejects a probability outside `0...1` as `malformedResponse`.

## Design

- `Question.Kind` gains `case verdict(yes: Option, no: Option)`. The `Option` id is the value to print; its description, when given, is the criterion for that side.
- Grammar: after the walk, a question with neither `--option` nor `--level` is a verdict, so the `has no --option or --level` error from wip/eh3 goes away. `--yes VALUE[=description]` and `--no VALUE[=description]` split at the first `=` like `--option`; an empty value is an error, `an --yes has no value`; each may appear at most once per question, a repeat is `question N ("...") repeats --yes`. Either flag on a question that has `--option` or `--level` is the mixed-kinds error from wip/eh3, worded to name the two flags involved, for example `question 2 ("...") mixes --option and --yes`. Defaults when a flag is absent: yes value `yes`, no value `no`. `--min-confidence` stays an unknown flag until wip/xhd.
- Runner: `QuestionSpec(id:, instructions: .text, kind: .verdict(ifTrue: yes.description.map { Criterion($0) }, ifFalse: no.description.map { Criterion($0) }))`. A bare value sends `nil`, not the value as a criterion: "Hell yeah" is what to print, not what to judge. Reading: a `.verdict` record is required, else `malformedResponse("The answer for qN is not a verdict.")`; a probability outside `0...1` or not finite is `malformedResponse` naming the question; the answer is the yes value when `probability >= 0.5`, else the no value; `Outcome.probabilities` is `[yes.id: p, no.id: 1 - p]`; `Outcome.confidence` is `record.confidence`.
- `Decide.usage`: the first paragraph says a question with no `--option` or `--level` is a yes/no question; the lines `--yes <value>[=<text>]` and `--no <value>[=<text>]` join the flag list.
- `Examples/ticket.sh` gains `"Should we issue a refund?" --yes Yes --no No` as a third question. Expected answer: Yes. wip/xhd adds the README's `--min-confidence 0.7` to that line.
- `Tests/DecideCoreTests/DecideLiveTests.swift`: the one live test grows to the three-question batch, still one request; it accepts any of the three team ids, any of the three level ids, and `Yes` or `No`.

## Location

- `Sources/DecideCore/Invocation.swift`: the `.verdict` case.
- `Sources/DecideCore/CommandLineParser.swift`: the two flags, the once-per-question rule, the bare-question default.
- `Sources/DecideCore/Runner.swift`: the verdict spec and the verdict read.
- `Sources/DecideCore/Decide.swift`: the usage text.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `RunnerTests.swift`, `DecideRunTests.swift`, `DecideLiveTests.swift`.
- `Examples/ticket.sh`.

## Tests

Swift Testing, `ScriptedModel`, no network except the live suite:

- Parser: the README line parses to `.verdict(yes: Option(id: "Hell yeah"), no: Option(id: "Forget it"))`, and the `Yes`/`No` form likewise; `--yes "Hell yeah"="Allowed by the policy"` gives the description; a bare question gives `.verdict(yes: Option(id: "yes"), no: Option(id: "no"))`; `--yes` alone leaves the no value `no`; a repeated `--yes` throws; `--yes ""` throws; `--option a --yes y` on one question throws the mixed-kinds error naming both flags; `--min-confidence 0.7` throws the unknown-flag error; the README batch example minus `--min-confidence 0.7` parses to three questions of three kinds.
- Runner: the spec carries `.verdict(ifTrue: nil, ifFalse: nil)` for bare values and criteria with the descriptions as summaries when given; probability 0.87 prints the yes value; 0.3 prints the no value; 0.5 prints the yes value (`>=`); probabilities are `[yes: p, no: 1 - p]`; confidence equals `AnswerRecord.verdict(probability: p).confidence`; a probability of 1.2 throws `malformedResponse` naming the question; a `.choice` record under a verdict question throws `malformedResponse`; three questions of three kinds make one request.
- Run: the batch prints `returns`, `somewhat_urgent`, `Yes` in order with a scripted model and returns 0; a bare question with a scripted 0.2 prints `no`.
- Live: `swift test --filter DecideLive` passes with a key and still sends one request.

## Related Issues

Parent: wip/nzu. Blocked on wip/eh3. wip/xhd adds `--min-confidence` on top of this. wip/28j, wip/wh2, wip/ayd hold the design notes of the code this changes.

## Acceptance Criteria

- [ ] `decide --context @Examples/ticket.txt "Should we issue a refund?" --yes "Hell yeah" --no "Forget it"` prints one of the two values and exits 0 against the real model.
- [ ] A bare question prints `yes` or `no`.
- [ ] `Examples/ticket.sh` runs three questions of three kinds and prints three lines from one request.
- [ ] A repeated `--yes`, an empty value, and mixed kinds each exit 2 with a message that names the problem.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, `swift test --skip DecideLive` passes, and `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-20 22:17:38-04:00 @ git:5efc7eb+local_

Design record, 2026-09-20 session, written before implementation. Corrections to the issue text: usage errors exit 10 (ExitCode.setup), not 2, since wip/fjj landed. Decisions: (1) Question.Kind gains 'case verdict(yes: Option, no: Option)'; Option.id is the value to print, Option.description the criterion for that side. (2) Grammar: after the walk a question with no kind flag is .verdict(yes: Option(id: "yes"), no: Option(id: "no")); --yes and --no each may appear once per question; the first of --yes/--no on a bare question fixes its kind as verdict. Messages, exact: 'a --yes has no value' and 'a --no has no value' (article 'a', matching 'a --level has no id'); 'question N ("...") repeats --yes'; mixed kinds keep the wip/eh3 rule, existing kind flag first, so 'mixes --option and --yes', 'mixes --level and --no', 'mixes --yes and --option'; '--yes before any question'; '--yes needs a value'. New rule not in the issue: the same value for both sides would collapse the probabilities dictionary, so 'question N ("...") uses the same value for --yes and --no' is an error. (3) Runner: spec is .verdict(ifTrue: yes.description.map { Criterion($0) }, ifFalse: no.description.map { Criterion($0) }); a bare value sends nil. Read: a .verdict record is required, else 'The answer for qN is not a verdict.'; a probability that is not finite or is outside 0...1 throws malformedResponse 'The answer for qN has probability P, outside 0 to 1.'; the answer is yes.id when p >= 0.5, else no.id; probabilities [yes.id: p, no.id: 1 - p]; confidence record.confidence, which the library computes as abs(2p - 1). (4) Usage line: 'Usage: decide --context <text> "<question>" [--option <id>... | --level <id>... | --yes <value> --no <value>] ["<question>" ...]...'; paragraph gains 'A question with no --option or --level is a yes/no question; it prints yes or no, or the --yes and --no values.'; two new flag lines. (5) DecideLiveTests grows to the three-question batch, one request; Examples/ticket.sh gains the refund question with --yes Yes --no No.

---

_📝 Noted on 2026-09-20 22:44:47-04:00 @ git:8c90147+local_

Worker done; diff read in the main context. Shape: KindFlag gains .yes and .no and a nested Group (choice, rating, verdict); add(_:as:to:) compares groups for the mixed-kinds message, sets the builder's flag only when nil (so the first flag is always named first), and holds the yes and no sides apart from values so a repeat throws 'repeats --yes' or 'repeats --no'; builder.question(number:) sends a flagless or verdict-flagged question to a private verdict(number:) that defaults the missing side and throws 'uses the same value for --yes and --no'. Runner.makeQuestionnaire sends .verdict(ifTrue:ifFalse:) from descriptions only; a private verdictOutcome guards the probability (finite, 0...1), answers at >= 0.5, and keys both probabilities by value. Tests 75 -> 92 in 5 suites, build clean with warnings as errors. Live by hand, three requests: swift test --filter DecideLive passed with the three-question batch; Examples/ticket.sh printed returns, urgent, Yes and exited 0; the README line --yes 'Hell yeah' --no 'Forget it' on ticket.txt printed 'Hell yeah' and exited 0.

---

_📝 Noted on 2026-09-20 22:56:49-04:00 @ git:8c90147+local_

Verifier: all five acceptance criteria hold, no blockers, no should-fixes, eight notes. Acted on: (1) the verdict probabilities were a dictionary literal, which traps on a repeated key; the parser's same-value guard is the only producer today, but the runner now builds the map with two assignments so a future question source cannot crash the process. (2) The usage first line lost its repeat marker and grew to 113 columns; it is now 'Usage: decide --context <text> "<question>" [<flags>] ["<question>" [<flags>]]...', and the flag list below explains the flags. (3) Three doc comments tightened: the builder's yes/no sentence, the same-value consequence (wrongly said 'one probability'), and missingID's scope (an empty value too). (4) Added a verdict-under-rating runner test. Left as is: KindFlag.noun's unreachable 'value' arm, documented in place; probability.isFinite in the verdict guard, redundant with the range check but a plain statement of intent that mirrors the library's own reader. Logged for later, not this issue: a --yes, --no, --option, or --level value that holds a newline prints as two lines and breaks the one-line-per-answer contract; pre-existing for --option, no test can see it, worth its own issue. Final: 93 tests in 5 suites, build clean with warnings as errors, live suite green with the three-question batch. Summary: a bare question is a yes/no verdict; --yes and --no set the two values and their criteria; three kinds mix in one batch and one request.
