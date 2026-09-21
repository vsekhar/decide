---
priority: p2
type: task
created: 2026-09-20T21:06:37-04:00
updated: 2026-09-20T22:35:51-04:00
blocked-on:
  - eh3
  - h9x
  - fjj
---

# Add --min-confidence: a per-question confidence bar for every kind, with an unsure exit code

## Objective

`--min-confidence <n>` after any question sets a bar on that answer's confidence. An answer at or above the bar prints as today. An answer below it, with no `--fallback` (not yet built), makes the run unsure: nothing on stdout, one line on stderr that names the question, its confidence, and the bar, and exit code 2.

## Context

The README uses `--min-confidence` in the Yes or no, Batch questions, and Errors sections, once on a choice question beside `--fallback human`. Decided with the user on 2026-09-20:

- Confidence is the library's number, DESIGN.md section 6.1 (`../DecisionModels/DESIGN.md`): the provider's reported confidence when it gives one (Jev does for choices and ratings), else the per-kind formula: choice `1 - H(p) / ln(n)`, rating `1 - sigma(p) / ((n - 1) / 2)` over level indices, verdict `abs(2p - 1)`. `AnswerRecord.confidence` computes it (`Sources/DecisionModels/AnswerRecord.swift`, `ConfidenceMath.swift`), and `Outcome.confidence` already carries it. It is the number a later `--json` prints, so the flag and the output agree.
- The rejected reading, "yes when P(yes) is at least the bar", fits verdicts and nothing else. Under the chosen reading the flag never turns "unsure" into "no": on a verdict, a confident no (P(yes) 0.05, confidence 0.9) passes a bar of 0.7 and prints the no value, while P(yes) 0.6 (confidence 0.2) is unsure. For a verdict, a bar of n means P(yes) at least (1 + n) / 2 for a yes or at most (1 - n) / 2 for a no; the usage text says so.
- Below the bar is its own outcome, not a default to no. It is decision-like: the arguments were good, the model and key worked, the server answered; only the content of the answer is "unsure". So it takes exit code 2, next to the decision codes, in the scheme wip/fjj sets up: 0 decided (yes under `--exit`), 1 no under `--exit`, 2 unsure, 3 to 9 reserved, 10 setup or input error, 11 remote error. Unsure is 2 with or without `--exit`. When `--fallback` lands, an unsure question with a fallback prints the fallback instead of failing the run.
- Scales differ per kind (a uniform three-level rating scores about 0.18, not 0, by the formula), which is why the bar is per question, as the README has it.

Blocked on wip/eh3 and wip/h9x, which give the parser its three kinds, and on wip/fjj, which frees code 2 and puts the row in the README tables.

## Design

- Grammar: `--min-confidence VALUE` and `--min-confidence=VALUE` after a question, on any kind. VALUE must parse as a `Double`, be finite, and lie in `0...1`, else `--min-confidence needs a number from 0 to 1, got "abc"`. At most once per question; a repeat is `question N ("...") repeats --min-confidence`. Before any question it is `--min-confidence before any question`. `Question` gains `minimumConfidence: Double?` beside `kind`; `nil` means no bar, so an absent flag never makes a run unsure, even at confidence 0.
- Runner: after every record is read into an `Outcome`, check each question that has a bar: `outcome.confidence < bar` marks it unsure. Collect them all, then throw `UnsureError(questions: [Unsure])`, where `Unsure` holds the 1-based question number, its instructions, `confidence`, and `minimumConfidence`. New file `Sources/DecideCore/UnsureError.swift`, both types `Equatable` and `Sendable`. Decided answers are not printed when any question is unsure: stdout stays empty on every non-zero exit, as today.
- `ExitCode`: `unsure: Int32 = 2`; `UnsureError` maps to it; the message is one line, `Error: unsure: question 3 ("Should we issue a refund?") has confidence 0.20, below the bar of 0.70`, with `; ` between several questions and two decimals on every number. The reserved-range test from wip/fjj (every code is 0 or at least 10) gains an exception for `UnsureError`, or is rewritten as "every code is 0, 2, or at least 10".
- `Decide.usage`: a `--min-confidence <n>` line, "The confidence an answer needs, from 0 to 1. Below it the run is unsure and exits 2. On a yes/no question, n means P(yes) at least (1 + n) / 2 for yes."; the exit-code line becomes `Exit codes: 0 decided, 2 unsure, 10 setup or input error, 11 remote error.`
- README: no change; wip/fjj already puts the row for 2 in both tables.
- `Examples/ticket.sh`: the refund question gains `--min-confidence 0.7`, so the script is the README batch example exactly. Its header comment says the run exits 2 when the model is unsure on the refund question, which is a real outcome worth showing.

## Location

- `Sources/DecideCore/Invocation.swift`: `Question.minimumConfidence`.
- `Sources/DecideCore/CommandLineParser.swift`: the flag and its checks.
- `Sources/DecideCore/Runner.swift`: the bar check after reading; `Sources/DecideCore/UnsureError.swift`: new.
- `Sources/DecideCore/ExitCode.swift`, `Sources/DecideCore/Decide.swift`: the code, the message, the usage text.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `RunnerTests.swift`, `ExitCodeTests.swift`, `DecideRunTests.swift`.
- `Examples/ticket.sh`.

## Tests

Swift Testing, `ScriptedModel`, no network:

- Parser: both value forms; the flag on a choice, a rating, and a verdict question; absent gives `nil`; `1.5`, `-0.1`, `abc`, `nan`, and `inf` each throw with the number message; a repeat throws; before any question throws; the full README batch example parses to three questions with the refund bar at 0.7 and `nil` on the other two.
- Runner, per kind: a choice record with reported confidence 0.6 under a bar of 0.7 is unsure and one with 0.8 is not; a choice record with no reported confidence uses the entropy formula (0.91/0.06/0.03 over three options gives about 0.67, so a bar of 0.6 passes and 0.7 does not); a rating record below and above its bar (compare against `AnswerRecord.rating(...).confidence`); a verdict at P(yes) 0.6 under 0.7 is unsure, 0.05 prints the no value, 0.95 prints the yes value; two unsure questions in one batch are both listed, in order; a bar of 0 with confidence 0 passes; no bar with confidence 0 passes.
- ExitCode: `UnsureError` maps to 2 in the table; its message is one line and holds the question number, its text, and both numbers with two decimals; the reserved-range test still passes with 2 allowed.
- Run: an unsure batch returns 2, stdout is empty, stderr is one line naming the question; the same batch at a bar of 0.1 prints three lines and returns 0.

## Related Issues

Follows wip/nzu, the parent of wip/eh3 and wip/h9x; blocked on both and on wip/fjj (the exit-code renumbering). wip/mfa holds the exit-code design and wip/wh2 the runner's. `--fallback` and `--exit` are separate, unfiled features that build on this outcome.

## Acceptance Criteria

- [ ] `Examples/ticket.sh` (the README batch example) exits 0 with three lines when the model is confident, and exits 2 with an empty stdout and one stderr line when it is not.
- [ ] `--min-confidence` works on all three kinds and compares against the same number `Outcome.confidence` holds.
- [ ] A bad value, a repeat, and the flag before any question each exit 10 with a message that names the problem.
- [ ] `Decide.usage` shows the flag and lists code 2.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, `swift test --skip DecideLive` passes, and `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-20 22:18:00-04:00 @ git:5efc7eb+local_

Design record, 2026-09-20 session, written before implementation. Decisions: (1) Question gains 'public var minimumConfidence: Double?' with init parameter 'minimumConfidence: Double? = nil' after kind; nil means no bar. (2) Parser: '--min-confidence VALUE' and '--min-confidence=VALUE' after a question, any kind, at most once. VALUE must parse as Double, be finite, and lie in 0...1. Messages, exact: '--min-confidence needs a number from 0 to 1, got "abc"' (the raw token in quotes; nan and inf fail this too); 'question N ("...") repeats --min-confidence'; '--min-confidence before any question'; '--min-confidence needs a value'. It is a modifier, not a kind flag, so it never trips the mixed-kinds rule. (3) New file Sources/DecideCore/UnsureError.swift: 'public struct UnsureError: Error, Equatable, Sendable { public let questions: [Unsure] }' and 'public struct Unsure: Equatable, Sendable { number: Int (1-based), instructions: String, confidence: Double, minimumConfidence: Double }'. (4) Runner.decide: after every record is read into an Outcome, collect each question whose bar is set and whose outcome.confidence < bar, in question order; if any, throw UnsureError. Decided answers are not printed; stdout stays empty on every non-zero exit. (5) ExitCode: 'public static let unsure: Int32 = 2'; code(for:) maps UnsureError to it before the default arm; message(for:) gives one line: 'Error: unsure: question 3 ("Should we issue a refund?") has confidence 0.20, below the bar of 0.70', several questions joined by '; ', two decimals via String(format: "%.2f"), passed through oneLine. The reservedRange test becomes 'every code is 0, 2, or at least 10' and the table gains UnsureError rows. (6) Usage: a line '--min-confidence <n>     The confidence an answer needs, from 0 to 1. Below it the run is unsure and exits 2. On a yes/no question, n means P(yes) at least (1 + n) / 2 for yes.' wrapped to the column, and 'Exit codes: 0 decided, 2 unsure, 10 setup or input error, 11 remote error.' (7) Examples/ticket.sh: the refund question gains --min-confidence 0.7 and the header says the run exits 2 when the model is unsure there. README: no change.

---

_📝 Noted on 2026-09-20 22:35:51-04:00 @ git:8c90147+local_

Addendum from wip/eh3's verification: Outcome.confidence is now the library's section 6.1 formula over the whole scale. Runner.decide fills every option or level the record leaves out at 0 before asking AnswerRecord.confidence, because the record alone infers the count from its own keys and would understate confidence when the provider omits a level (0.08 versus 0.54 in the probe). A reported confidence still wins. So --min-confidence gates on the whole-scale number; the xhd runner tests that compare against AnswerRecord.rating(...).confidence must build the record with all levels present, or pin literals (0.3462 for [0.15, 0.55, 0.30] on three levels, 0.4439 for a 0.7/0.3 choice among three options).
