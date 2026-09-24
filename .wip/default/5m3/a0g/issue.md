---
priority: p2
type: task
created: 2026-09-24T02:48:49-04:00
updated: 2026-09-24T02:49:20-04:00
may-unblock:
  - oin
---

# An unsure question prints an empty answer; the other lines print, exit 2, stderr says Unsure:

## Objective

A question below its `--min-confidence` bar no longer takes the whole run down. Every question keeps its line, in order: a sure question prints its answer, and an unsure one prints an empty answer, `refund=` for a named question and a blank line for an unnamed one. The run exits 2 and stderr says which questions were unsure and why, with the prefix `Unsure:` instead of `Error: unsure:`. `--json` prints its line too, with `"answer": null` and `"unsure": true` for the unsure question. Nothing about the model's numbers changes: `--stats` and `--distribution` still print them on the unsure line, and the JSON still carries the confidence and the probabilities.

```sh
$ decide --context @ticket.txt \
     "Which team handles this ticket?" --name team \
         --option shipping --option billing --option returns \
     "Should we issue a refund?" --name refund --min-confidence 0.9
team=returns
refund=
stderr> Unsure: question 2 ("Should we issue a refund?") has confidence 0.74, below the bar of 0.90
$ echo $?
2
```

## Context

Decided with the user on 2026-09-24 (see wip/5m3 for the whole design). `--min-confidence` is already per question on the input side: the parser attaches it to the question it follows (`setMinimumConfidence`), and a JSON file's `min-confidence` key does the same. What is whole-run today is the failure. `Runner.decide` collects every question below its bar into one `UnsureError`, `Decide.run` prints nothing on stdout, `ExitCode.message(for:)` prints one `Error: unsure: question 3 ("...") has confidence 0.20, below the bar of 0.70` line on stderr, and the code is 2. The sure answers are thrown away.

The empty answer cannot collide with a real one: the parser and the JSON decoder refuse an empty option, level, or side value. The rule that exit 0 means every line is a decision still holds. The rule that non-empty stdout means exit 0 goes away, and the README says so.

How the code stands:

- `Runner.decide(_:about:using:)` returns `[Outcome]` or throws `UnsureError(questions: [Unsure])`. `Outcome` holds the model's answer, confidence, probabilities, and score. `Unsure` holds the number, the instructions, the confidence, and the bar, for the message.
- `Decide.run` prints outcomes through `PlainOutput.line(for:outcome:)` or `JSONOutput.line(for:outcomes:)`, and every error through `ExitCode.message(for:)`. `exitCode(for:questions:)` gives 0, or the side's code for one yes/no question.
- `ExitCode.code(for:)` maps `UnsureError` to 2; `ExitCodeTests.unsureMessage` and four `DecideRunTests` assert the current all-or-nothing behavior; `RunnerTests` has five bar tests that expect the throw.

## Location

- `Sources/DecideCore/Runner.swift`: `Outcome.unsure`, `decide` no longer throws for the bar.
- `Sources/DecideCore/UnsureError.swift`: `UnsureError` goes; `Unsure` stays and gains the stderr line.
- `Sources/DecideCore/ExitCode.swift`: drop the `UnsureError` cases.
- `Sources/DecideCore/PlainOutput.swift`, `JSONOutput.swift`: the empty answer and the null answer.
- `Sources/DecideCore/Decide.swift`: print every line, then the `Unsure:` line, then exit 2; the usage text.
- `README.md`: the example above and one sentence under Exit codes.
- `Tests/DecideCoreTests/RunnerTests.swift`, `ExitCodeTests.swift`, `PlainOutputTests.swift`, `JSONOutputTests.swift`, `DecideRunTests.swift`.

## Approach

**Outcome.** `Outcome` gains `public let unsure: Bool`, with `unsure: Bool = false` last in the init so every call site compiles. `Runner.decide` sets it where it builds the `Unsure` list today: `question.minimumConfidence` is set and `outcome.confidence < bar`. It no longer throws `UnsureError`; the doc comment's last paragraph changes to say the outcome carries the bar's result. Keep `Unsure` as the message record and add `public static func report(_ questions: [Unsure]) -> String` on it, or beside it, giving `Unsure: question 3 ("Should we issue a refund?") has confidence 0.20, below the bar of 0.70`, with `; ` between clauses as today; move the body of `ExitCode.message(for: UnsureError)` there and delete `UnsureError`, its `ExitCode` cases, and `ExitCodeTests.unsureMessage` (the test moves with the function). Keep the two-decimal format and the wording of each clause, so only the prefix changes. Rename the file if the type is gone, or keep the name; the worker's call.

**Plain output.** `PlainOutput.line(for:outcome:)` prints the answer part as `""` when `outcome.unsure`, so the line is `name=` or empty, and the stats and distribution fields follow as they do now: `confidence:` is the model's confidence and `probability:` is the top probability, the one the model would have printed. The doc comment says what an empty answer means.

**JSON output.** `JSONOutput.value` prints `"answer":null` when unsure and adds `"unsure":true` right after it, before `score` or `verdict`; a verdict's `"verdict"` is `null` too. No `unsure` key on a sure question, so every existing line is unchanged. The header comment lists the key.

**Run.** `Decide.run` no longer catches an unsure error. After printing the lines, it collects the unsure questions in order, `Unsure(number: index + 1, instructions:, confidence:, minimumConfidence:)`, prints `Unsure.report` to stderr when there are any, and returns `ExitCode.unsure`; else the existing `exitCode(for:questions:)`. Stdout lines come first, then the stderr line. With `--quiet`, nothing prints on stdout as now, the stderr line prints, and the code is 2. With `--json`, the JSON line prints, then the stderr line, code 2.

**Usage text.** The `--min-confidence` entry: "The confidence an answer needs, from 0 to 1. Below it the answer prints empty, the run exits 2, and stderr names the question. On a yes/no question, n means P(yes) at least (1 + n) / 2 for yes." Update the usage-text tests that assert this block.

**README.** Add the example above under Advanced usage, before Statistics, titled "Confidence bars", with two sentences: a question below its bar prints an empty answer and the others print theirs; the run exits 2 and stderr names each unsure question with its confidence and its bar. Under Exit codes, after "Only 0 and 1 carry an answer", add: "Exit 2 prints every line; the unsure ones are empty. Check the code before reading stdout." Leave the `--fallback` sentences to wip/oin.

## Out of Scope

- `--fallback`: wip/oin adds it on top of this one.
- Remote errors: no output and exit 11, unchanged.
- Any change to the numbers, the bar rule, or the wire.

## Tests

- Runner: the five bar tests (`choiceBar`, `choiceBarWithoutReportedConfidence`, `ratingBar`, `verdictBar`, `twoUnsureQuestions`, `zeroBar`) assert `outcome.unsure` instead of the throw; a sure question has `unsure == false`; a question with no bar is never unsure.
- Unsure: `report` for one and for two questions gives the old text with the new prefix.
- PlainOutput: an unsure named question prints `name=`; unnamed prints `""`; with `--stats` the tab fields follow the empty answer; with `--distribution` every field prints.
- JSONOutput: an unsure choice, rating, and verdict print `"answer":null,"unsure":true` with the numbers; a verdict's `verdict` is `null`; key order is asserted.
- Run (scripted model): the README batch with the refund below its bar prints `returns\nsomewhat_urgent\n\n` and exits 2 with the `Unsure:` line on stderr; the named example above prints `team=returns\nrefund=\n`; `--json` prints the line with the null answer and exits 2; `-q` with an unsure yes/no prints nothing and exits 2; two unsure questions are both listed; `--distribution` on an unsure question prints its fields; the usage-text tests.
- No live test: a scripted model proves it, and the wire does not change (TESTING.md).

## Related Issues

- Parent: wip/5m3.
- Sibling: wip/oin (`--fallback`), blocked on this issue.
- wip/xhd added `--min-confidence` and the all-or-nothing unsure exit; wip/mb3 added the stats fields this issue keeps on an empty line; wip/4qk added `--json`.

## Acceptance Criteria

- [ ] A run with one unsure question among sure ones prints every line in order, the unsure one empty, and exits 2.
- [ ] Stderr names each unsure question, its confidence, and its bar, prefixed `Unsure:`.
- [ ] `--json` keeps the key with `"answer": null` and `"unsure": true` and the model's numbers; sure lines are byte-for-byte as before.
- [ ] `--stats` and `--distribution` fields print on an unsure line; `-q` prints nothing and exits 2.
- [ ] `--help` and the README describe the empty answer; `UnsureError` is gone.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.
