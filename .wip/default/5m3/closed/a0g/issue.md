---
priority: p2
type: task
created: 2026-09-24T02:48:49-04:00
updated: 2026-09-24T03:46:32-04:00
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

---

_📝 Noted on 2026-09-24 03:37:10-04:00 @ git:4c04357+local_

Design record (2026-09-24), start. Everything below is verbatim for code and docs unless marked "worker's call".

## Types

1. `Outcome` (Runner.swift) gains, after `score`:

```swift
    /// Whether the answer fell below the question's `--min-confidence` bar.
    /// The numbers above are the model's either way. The line for an unsure
    /// question prints no answer, and the run exits 2.
    public var unsure: Bool
```

and `unsure: Bool = false` last in the init, so every call site compiles. A `var`, so `Runner.decide` can mark an outcome after the kind-specific builders make it.

2. `UnsureError` goes. The file `UnsureError.swift` becomes `Unsure.swift` (git mv), holds `import Foundation` and the `Unsure` struct with this doc comment and one new static:

```swift
/// One question whose answer fell below its `--min-confidence` bar. The run
/// prints an empty answer on its line, reports every such question on stderr
/// through `report`, and exits 2.
public struct Unsure: Equatable, Sendable {
    // the four fields and the init as they are

    /// The stderr line for the unsure questions, in question order, with no
    /// trailing newline: `Unsure: question 3 ("Should we issue a refund?")
    /// has confidence 0.20, below the bar of 0.70`, one clause per question,
    /// joined by `; `. Two decimals, so the line reads at a glance; `--stats`
    /// prints three and `--json` the exact value. One line whatever the
    /// question text holds.
    public static func report(_ questions: [Unsure]) -> String
```

The body is the old `ExitCode.message(for: UnsureError)` with the prefix `Unsure: ` and the result passed through `ExitCode.oneLine`, which becomes internal (`static func oneLine`) with its doc comment kept.

3. `ExitCode`: drop `case is UnsureError` from `code(for:)`, `case let error as UnsureError` from `message(for:)`, and the private `message(for: UnsureError)`. `ExitCode.unsure` stays.

## Runner

4. `Runner.decide` no longer throws for the bar. After the outcomes are built, mark each whose question has a bar and whose confidence is below it (`outcome.confidence < bar`, the same comparison as today), and return them. Replace the doc paragraph that starts "Throws `DecisionError.malformedResponse`" with:

```
    /// Throws `DecisionError.malformedResponse` when a question comes back
    /// with no answer, or when the library rejects a record. A question with
    /// a bar whose answer falls below it comes back with `unsure` set, and
    /// nothing is thrown for it: the bar compares against the same number
    /// `Outcome.confidence` holds.
```

5. New on `Runner`, below `decide`:

```swift
    /// The unsure questions of a run, in question order, for the stderr
    /// line: each outcome marked `unsure`, paired with its question's bar.
    /// `questions` and `outcomes` pair up by position, as `decide` gives
    /// them. Empty when every answer cleared its bar.
    public static func unsureQuestions(in questions: [Question], outcomes: [Outcome]) -> [Unsure]
```

Number is `index + 1`; instructions, confidence, and the bar as today's `Unsure` records held them.

## Output

6. `PlainOutput.line`: the answer part is `""` when `outcome.unsure`, so the line is `name=` or empty; every field after it prints as it does now. The header comment gains this paragraph after the first one:

```
/// An answer below the question's `--min-confidence` bar prints as nothing,
/// so the line is `name=` or empty. The fields after it are the model's
/// numbers as they stand, and `probability:` is the probability of the
/// answer the model would have given. The run exits 2 and names the
/// question on stderr.
```

7. `JSONOutput.value`: `"answer"` is `null` when `outcome.unsure`, followed by `"unsure":true`, before `score` or `verdict`; a verdict's `"verdict"` is `null` when unsure. No `unsure` key on a sure answer, so every existing line is byte-for-byte unchanged. Worker's call how to share the two pairs across the three kinds. The header comment gains, after the first paragraph:

```
/// An answer below the question's `--min-confidence` bar has `"answer": null`
/// and then `"unsure": true`, and a verdict's `verdict` is null too; the
/// numbers are the model's as they stand. A sure answer has no `unsure` key,
/// so its object is unchanged.
```

Shapes, exact:

- choice: `{"kind":"choice","answer":null,"unsure":true,"confidence":0.6,"probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}}`
- rating: `{"kind":"rating","answer":null,"unsure":true,"score":1.2,"confidence":0.3,"probabilities":{...}}`
- verdict: `{"kind":"verdict","answer":null,"unsure":true,"verdict":null,"confidence":0.6,"probabilities":{"Yes":0.8,"No":0.2}}`

## Run

8. `Decide.run`: the `catch` around `Runner.decide` no longer sees an unsure error. After the lines print (plain or JSON, or nothing with `--quiet`), compute `Runner.unsureQuestions(in:outcomes:)`. When it is not empty, print `Unsure.report(...)` to stderr and return `ExitCode.unsure`; else `exitCode(for:questions:)` as today. Stdout lines first, then the stderr line. In the `run` doc comment, after "everything else goes to `stderr`.", add: "An answer below its bar prints empty; the run reports it on `stderr` and exits 2 after every line has printed."

9. Usage text, the `--min-confidence` entry, in the current column:

```
          --min-confidence <n>           The confidence an answer needs, from 0 to 1. Below it
                                         the answer prints empty, the run exits 2, and stderr
                                         names the question. On a yes/no question, n means
                                         P(yes) at least (1 + n) / 2 for yes.
```

## Docs

10. README, under "## Advanced usage", a new subsection right before "### Statistics: confidence and probabilities":

````
### Confidence bars

```sh
# A question below its --min-confidence bar prints an empty answer; the others print theirs
$ decide --context @ticket.txt \
     "Which team handles this ticket?" \
         --name team \
         --option shipping \
         --option billing \
         --option returns \
     "Should we issue a refund?" \
         --name refund \
         --min-confidence 0.9
team=returns
refund=

stderr>  Unsure: question 2 ("Should we issue a refund?") has confidence 0.74, below the bar of 0.90
$ echo $?
2
```

The run exits 2 when any question is below its bar, after every line has printed. Check the exit code before you read stdout.
````

11. README, "### Exit codes", after the paragraph "Only 0 and 1 carry an answer. ... or switch on `$?`.", a new paragraph:

```
Exit 2 prints every line, and the unsure ones are empty. Check the code before you read stdout.
```

12. DEVELOPMENT.md, Layout: the line naming `UnsureError.swift` becomes:

```
- `Sources/DecideCore/Runner.swift`, `Unsure.swift`: one questionnaire for
  every question, one request, answers back in question order, each marked
  when it is below its bar.
```

13. TESTING.md, "One suite at a time": add `Unsure` to the list of suite names, after `Runner`.

## Tests

14. `RunnerTests`: `choiceBar`, `choiceBarWithoutReportedConfidence`, `ratingBar`, `verdictBar`, `twoUnsureQuestions` assert `unsure` on the outcome instead of the throw, keep every assertion on the answer, and where they compared `UnsureError.questions` compare `Runner.unsureQuestions(in:outcomes:)` to the same `Unsure` records. `zeroBar` gains `unsure == false` on its outcomes. Add: a question with no bar is never unsure whatever its confidence.

15. `ExitCodeTests`: drop the `UnsureError` row of `errorTable` and `unsureMessage`.

16. New `Tests/DecideCoreTests/UnsureTests.swift`, `@Suite("Unsure")`: `report` for one and for two questions gives the old text with the new prefix (the two strings from `unsureMessage`, `Error: unsure:` replaced by `Unsure:`); instructions holding `\n` give one line with a space there.

17. `PlainOutputTests`: an unsure named choice prints `team=`; unnamed prints an empty string; with `.stats` the tab fields follow the empty answer; with `.distribution` every field prints; a sure outcome is unchanged.

18. `JSONOutputTests`: the three shapes in item 7, with the test file's outcomes marked `unsure: true`; a sure line is unchanged.

19. `DecideRunTests`: `unsureBatch` expects `returns\nsomewhat_urgent\n\n` and `Unsure: question 3 ("Should we issue a refund?") has confidence 0.20, below the bar of 0.70\n` on stderr; `unsureVerdict` expects `\n` on stdout and the `Unsure:` line; `namedUnsure` expects `spam=\n`; `distributionUnsure` expects the empty answer then its stats and both side fields; `jsonUnsure` expects the one JSON line with the null answer for the refund and the other two objects unchanged; `jsonFileUnsure` expects `team=returns\nurgency=somewhat_urgent\nrefund=\n` and the `Unsure:` line; add `-q` with a yes/no question below its bar: stdout empty, the `Unsure:` line, exit 2; add the README's Confidence bars example against `triageModel` (refund confidence 0.74): `team=returns\nrefund=\n`, stderr `Unsure: question 2 ("Should we issue a refund?") has confidence 0.74, below the bar of 0.90\n`, exit 2. Test titles change to say what prints.

## Out of scope

`--fallback` (wip/oin). Remote errors. The numbers, the bar rule, the wire. No live test.

---

_📝 Noted on 2026-09-24 03:43:13-04:00 @ git:4c04357+local_

Implementation (2026-09-24), worker's calls accepted on review: (1) README Confidence bars run test uses model(answering: [teamAnswer, .verdict(probability: 0.87)]) rather than triageModel, which answers only q1..q3 and not the named ids; same numbers. (2) JSON output tests use the test file's own outcomes (team 0.91 etc.) with the design's key order, plus a sure-beside-unsure test proving a sure object is unchanged. (3) New usageListsTheBar test asserts the four-line --min-confidence entry word for word; none existed. (4) New run test twoUnsureQuestions: team at 0.95 and refund at 0.7, stdout '\nsomewhat_urgent\n\n', both on one Unsure: line. (5) JSONOutput shares the answer/unsure pair through a private answer(_:) helper; Runner.decide marks outcomes in a loop over a var array. Main-context fix after hand-back: DecideLiveTests.triagesFromAJSONFile expected the old empty stdout and 'Error: unsure: ' prefix on exit 2; it now expects three lines with 'refund=' last and 'Unsure: question 3 ' on stderr, and the same three-line check on either code. Nothing committed yet.

---

_📝 Noted on 2026-09-24 03:46:32-04:00 @ git:4c04357+local_

Summary (2026-09-24): done. Runner.decide marks each outcome unsure when its confidence is below its bar and throws nothing for it; Runner.unsureQuestions(in:outcomes:) lists them; Unsure.report builds the stderr line with the Unsure: prefix through ExitCode.oneLine; UnsureError and its ExitCode cases are gone (file renamed Unsure.swift). PlainOutput prints an empty answer and JSONOutput prints answer null plus unsure true (verdict null) on an unsure line; Decide.run prints every line, then the report, and exits 2. Usage text, README (Confidence bars section, Exit codes paragraph), DEVELOPMENT.md, TESTING.md updated. Verifier: all six criteria hold, no blockers; its one test-gap note led to DecideRunTests.unsureVerdictNo (a would-be no below its bar exits 2, not 1), proved by a mutant that fell through to the answer's code and failed it. Its latent note, that unsureQuestions drops an unsure outcome on a question with no bar, is unreachable through Runner.decide and is resolved by wip/oin's exit-code check on outcome.unsure. 467 offline tests and 5 live tests pass.
