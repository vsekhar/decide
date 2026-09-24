---
priority: p2
type: task
created: 2026-09-24T02:48:53-04:00
updated: 2026-09-24T03:59:43-04:00
blocked-on:
  - a0g
---

# Add --fallback: what an unsure question prints, and a remote error when every question has one

## Objective

`--fallback <value>` after a question names what that question prints when the model cannot decide it: when its answer is below its `--min-confidence` bar, or when the run has a remote error. A question that prints its fallback counts as decided, so a run whose every unsure question has a fallback exits 0, and one yes/no question exits with its fallback's side. A JSON question file writes it as `"fallback": "human"`.

```sh
# Below the bar, the fallback prints and the run is decided
$ decide --context @ticket.txt \
     "Which team handles this ticket?" --name team \
         --option shipping --option billing --option returns \
         --min-confidence 0.9 --fallback human \
     "Should we issue a refund?" --name refund
team=human
refund=Yes
stderr> Unsure: question 1 ("Which team handles this ticket?") has confidence 0.74, below the bar of 0.90
$ echo $?
0

# A remote error prints every fallback when every question has one
$ sudo ip link set eth0 down
$ decide --context "$body" "Which team handles this ticket?" \
         --option shipping --option billing --option returns --fallback human
stderr> Error: cannot reach decision model server
human
$ echo $?
0

# A yes/no fallback is one of its two values, so a script's branch is safe
if decide --context "$body" "Is this message spam?" -q --fallback no; then
  mv "$file" spam/     # never reached on an error
fi
```

A remote error on a run where any question has no fallback stays as it is: nothing on stdout, exit 11. The tool cannot assert it is unsure of anything then, so an empty answer would say something false.

## Context

Decided with the user on 2026-09-24; wip/5m3 holds the whole design. The README's Errors section already promises `--fallback` and shows the network-down example, but it writes `-q --fallback false` with default `yes`/`no` sides and a sentence about "the fallback exit code" that means nothing defined. The decision here: a yes/no question's fallback must be its yes value or its no value, so the exit code always follows a side, `--fallback false` in the README becomes `--fallback no`, and the sentence goes. Any other kind takes any value; it need not be an option or level id, as the README's `human` shows.

This issue builds on wip/a0g, which prints every line: `Outcome.unsure`, `Unsure.report`, the empty answer, and the `Unsure:` stderr line. It adds a second thing an unsure line can print, and a remote-error path that prints with no outcomes at all.

How the code stands after wip/a0g:

- `Question` (`Invocation.swift`) has `minimumConfidence`, `name`, `rules`, `detail`. The parser builds one through `QuestionBuilder`, where the sides of a yes/no question are known only at `question(number:)` time, since `--yes` may come after any flag. `JSONQuestionFile.QuestionBody` lists the allowed keys and checks each.
- `QuestionFile.valueFlags` lists the flags a text question file may hold; `--min-confidence` and `--name` are there.
- `PlainOutput.line` and `JSONOutput.value` print an unsure outcome as empty or null; `Decide.run` prints the lines, then `Unsure.report`, and returns 2 when any outcome is unsure; `exitCode(for:questions:)` compares `outcome.answer` to the yes side for one yes/no question.
- `Decide.run` catches every error from `Runner.decide` with `ExitCode.message(for:)` and `ExitCode.code(for:)`; the remote ones are exactly those `code(for:)` maps to `ExitCode.remote`, unknown errors included.
- `ScriptedModel { _ in throw DecisionError.timeout }` is how `DecideRunTests.timeout` scripts a remote error.

## Location

- `Sources/DecideCore/Invocation.swift`: `Question.fallback`.
- `Sources/DecideCore/CommandLineParser.swift`: `--fallback` in the main loop, `QuestionBuilder`, the side check.
- `Sources/DecideCore/QuestionFile.swift`: `valueFlags`.
- `Sources/DecideCore/JSONQuestionFile.swift`: the `fallback` key.
- `Sources/DecideCore/Runner.swift` or a new small file: the printed answer of a question and outcome, shared by both printers and the exit code.
- `Sources/DecideCore/PlainOutput.swift`, `JSONOutput.swift`: the fallback on an unsure line, and the fallback-only line for a remote error.
- `Sources/DecideCore/Decide.swift`: the remote path, the exit code, the usage text.
- `README.md`: the Errors section, the `--fallback` sentences under Exit codes, the JSON question file example.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `QuestionFileTests.swift`, `JSONQuestionFileTests.swift`, `PlainOutputTests.swift`, `JSONOutputTests.swift`, `DecideRunTests.swift`.

## Approach

**Question.** `Question` gains `public var fallback: String?`, default nil in the init, documented as what the question prints when it is unsure or the run has a remote error.

**Parser.** `--fallback <value>` and `--fallback=<value>` join the last question like `--min-confidence`: `lastBuilder`, once per question (`question 1 ("...") repeats --fallback`), on a question of any kind, with or without a bar. The value is non-empty and holds no tab, line feed, or carriage return, the `checkedID` rule, with messages `a --fallback has no value` and `a --fallback value holds a tab or newline`. In `QuestionBuilder.verdict(number:)`, after the sides are settled, a fallback that is neither `yesSide.id` nor `noSide.id` throws `question 1 ("...") has a fallback "maybe" that is not its --yes or --no value`. `--quiet` needs no new rule: it already needs one yes/no question, whose fallback is a side. The `parse` doc comment gains a sentence.

**Question files.** Add `--fallback` to `QuestionFile.valueFlags`, so a text file may hold it. In `JSONQuestionFile`, `QuestionBody` allows the key `fallback`, a string (`expected a string`), and `question(number:)` applies the same three checks with paths `questions[i].fallback`: `is empty`, `holds a tab or a newline`, and for a yes/no question `is not the yes or no value`.

**The printed answer.** One helper decides what a question's line shows, so plain output, JSON output, and the exit code agree: the outcome's answer when it is sure; the question's fallback when it is unsure and has one; nil when it is unsure and has none. Put it as a static on `Runner` or next to `Outcome`, `answer(for question: Question, outcome: Outcome) -> String?`. `PlainOutput.line` prints it, empty for nil. `JSONOutput.value` prints `"answer"` from it and then the state keys: `"unsure":true` when the outcome is unsure, and `"fallback":true` when the answer is the fallback, in that order, before `score` or `verdict`; a verdict's `"verdict"` follows the printed answer, so a fallback of the yes value gives `true`. The stats and distribution fields stay the model's numbers, and the doc comment says that `probability:` is the model's answer's probability even when the fallback prints.

**Remote errors.** In `Decide.run`, where the catch around `Runner.decide` is: when `ExitCode.code(for: error) == ExitCode.remote` and every question has a fallback, print the error's message to stderr as today, then print one line per question with its fallback on stdout, and return the decided code, the fallback's side for one yes/no question. The plain line is `[name=]fallback` with no tab fields, even with `--stats`, because there are no numbers; the JSON line has `kind`, `answer`, `"fallback":true`, and `verdict` for a yes/no question, and no `score`, `confidence`, or `probabilities`. Add `PlainOutput.fallbackLine(for:)` and `JSONOutput.fallbackLine(for:)` for these. When any question has no fallback, the run is as today: message, nothing on stdout, exit 11. A setup error (exit 10) never takes a fallback.

**Exit code.** After the lines print: the `Unsure:` line prints when any outcome is unsure, fallback or not, so the reader knows the model was below the bar. The code is 2 when any unsure outcome has no fallback; else `exitCode(for:questions:)`, which now compares the printed answer, so one yes/no question with a fallback of its no value exits 1.

**Usage text.** After `--min-confidence`: `--fallback <value>   What this question prints when its answer is below its bar, or when the model server fails. A yes/no question's fallback is its --yes or --no value.` Wrapped in the current column; update the usage-text tests.

**README.** Rewrite the Errors section with the three examples above and one paragraph: a fallback prints in place of an unsure answer or on a remote error; a question that prints its fallback counts as decided; a remote error prints fallbacks only when every question has one, else nothing and exit 11. Under Exit codes, replace the two `--fallback` sentences with: "`--fallback` on a question makes an unsure answer a decision and, when every question has one, a remote error too. With one yes/no question the fallback is its yes or no value, and the code follows that side." Add `"fallback": "human"` to the `team` question of the JSON example under Question files, or leave the example alone and mention the key in a sentence; the worker's call.

## Out of Scope

- Streaming and `--each`: the per-event rule in the README stays a promise.
- A run-wide fallback flag, or a fallback for setup errors.
- Retrying the request.

## Tests

- Parser: `--fallback human` on a choice sets `Question.fallback`; the `=` form; on a rating; on a yes/no question with the default sides, `yes` and `no` pass and `maybe` throws the side message; with `--yes spam --no ham`, `ham` passes and `no` throws; `--fallback` before `--yes` still checks against the final sides; repeated, empty, tab, before any question, and after a `.questions` item each throw their message; `-q` with `--fallback no` parses.
- Question files: a text file holding `--fallback human` splices it; a JSON question with `"fallback": "human"` decodes; an empty, tabbed, or non-side fallback names `questions[i].fallback`; a non-string is `expected a string`.
- PlainOutput and JSONOutput: an unsure choice with a fallback prints `team=human` with the model's stats fields, and `"answer":"human","unsure":true,"fallback":true` with the numbers; a yes/no fallback of the yes value gives `"verdict":true`; the remote fallback lines have no fields and no numbers.
- Run (scripted model): the first README example above prints `team=human\nrefund=Yes\n`, the `Unsure:` line, exit 0; the same without the fallback prints `team=\nrefund=Yes\n` and exits 2 (wip/a0g's behavior, kept); a yes/no question below its bar with `--fallback no` exits 1 and with `--fallback yes` exits 0, and with `-q` prints nothing; a model that throws `DecisionError.timeout` with every question carrying a fallback prints the fallbacks, the timeout message on stderr, and exits 0, or the side for one yes/no; the same with one question lacking a fallback prints nothing and exits 11; `--json` on both paths; a `.unauthorized` (exit 10) with fallbacks prints nothing and exits 10; the usage-text tests.
- No live test: a scripted model proves it, and the wire does not change (TESTING.md).

## Related Issues

- Parent: wip/5m3.
- Blocked on wip/a0g, which prints every line and adds `Outcome.unsure`.
- wip/xhd (`--min-confidence`), wip/hah and wip/rqr (the JSON question file and its strict keys), wip/qc4 (the text file's allowed flags), wip/brs (one yes/no question's exit code).

## Acceptance Criteria

- [ ] `--fallback` after a question, and `fallback` in a JSON question file, print in place of an unsure answer; the run exits 0 when every unsure question has one, and one yes/no question exits with the fallback's side.
- [ ] A yes/no question's fallback must be its yes or no value; any other kind takes any non-empty single-line value.
- [ ] A remote error prints every fallback and the error line and exits as decided when every question has a fallback, and prints nothing with exit 11 otherwise; a setup error never takes a fallback.
- [ ] `--json` marks a fallback with `"fallback": true`, keeps `"unsure": true` when the model was below the bar, and carries no numbers on the remote path.
- [ ] The README's Errors section runs as written with `--fallback no`, and `--help` lists the flag.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-24 03:46:52-04:00 @ git:a2d24c9+local_

Design record (2026-09-24), start. Builds on wip/a0g as landed: `Outcome.unsure`, `Unsure.report`, `Runner.unsureQuestions(in:outcomes:)`, the empty answer in both printers. Everything below is verbatim for code and docs unless marked "worker's call".

## Question

1. `Question` (Invocation.swift) gains, after `minimumConfidence`, with `fallback: String? = nil` after `minimumConfidence` in the init:

```swift
    /// What the question prints instead of its answer when that answer is
    /// below its bar, or when the run has a remote error, from `--fallback`
    /// or a JSON file's `fallback`. nil when the question has none. On a
    /// yes/no question it is the yes value or the no value, so the exit code
    /// of a one-question run still follows a side.
    public var fallback: String?
```

## Parser

2. `--fallback <value>` and `--fallback=<value>` join the last question through `lastBuilder`, in the main loop right after `--min-confidence`. `QuestionBuilder` gains `var fallback: String?` and passes it to each `Question` it builds. Rules and messages:
   - a second `--fallback` on one question: `question 1 ("...") repeats --fallback` (the `label` form, like `repeats --min-confidence`)
   - an empty value: `a --fallback has no value`
   - a value holding a tab, a line feed, or a carriage return: `a --fallback value holds a tab or newline`
   - in `QuestionBuilder.verdict(number:)`, after the sides are settled and the same-value guard: a fallback that is neither `yesSide.id` nor `noSide.id`: `question 1 ("...") has a fallback "maybe" that is not its --yes or --no value`
   - before any question, or right after a `.questions` item: `lastBuilder`'s two messages, for free.
   `=` is allowed in a fallback; only whitespace that breaks a line is not. `--quiet` needs no new rule.

3. The `parse` doc comment, after the `--min-confidence` sentence: "`--fallback` after a question names what it prints when its answer is below its bar or the run has a remote error; on a yes/no question it is the yes or no value."

## Question files

4. `QuestionFile.valueFlags` gains `"--fallback"`, so a text file may hold it.

5. `JSONQuestionFile`: `QuestionBody` allows the key `fallback`, read with `object.optional("fallback", String.self, "a string")`. In `question(number:)`, after the kind is built, with path `\(path).fallback`:
   - empty: `is empty`
   - a tab, line feed, or carriage return: `holds a tab or a newline`
   - a yes/no question whose fallback is neither side's id: `is not the yes or no value`
   The header doc's sentence "It may have a `name`, a `min-confidence`, and `stats` and `distribution` flags." becomes "It may have a `name`, a `min-confidence`, a `fallback`, and `stats` and `distribution` flags."

## The printed answer

6. New on `Runner`, below `unsureQuestions`:

```swift
    /// What a question's line shows: the outcome's answer when it cleared
    /// its bar, the question's fallback when it did not and has one, and nil
    /// when it did not and has none, which prints as an empty answer. Plain
    /// output, JSON output, and the exit code all read this, so they agree.
    public static func printedAnswer(for question: Question, outcome: Outcome) -> String?
```

7. `PlainOutput.line` prints `Runner.printedAnswer(for:outcome:) ?? ""` where wip/a0g printed the empty answer. The header paragraph wip/a0g added becomes:

```
/// An answer below the question's `--min-confidence` bar prints as nothing,
/// so the line is `name=` or empty, or as the question's `--fallback` when
/// it has one. The fields after it are the model's numbers as they stand,
/// and `probability:` is the probability of the answer the model would have
/// given, fallback or not. The run names the question on stderr either way,
/// and exits 2 when an unsure question has no fallback.
```

8. `JSONOutput.value`: `"answer"` is the printed answer, or `null`; then `"unsure":true` when `outcome.unsure`; then `"fallback":true` when the printed answer is the fallback; then `score` or `verdict`, where a verdict's `"verdict"` follows the printed answer: `null` for none, `true` when it is the yes value, `false` otherwise. The header paragraph wip/a0g added becomes:

```
/// An answer below the question's `--min-confidence` bar has `"answer": null`
/// and then `"unsure": true`, or the question's fallback and then
/// `"unsure": true, "fallback": true`; a verdict's `verdict` follows the
/// printed answer, null for none. The numbers are the model's as they
/// stand. A sure answer has neither key, so its object is unchanged.
```

Shapes, exact:
- unsure choice with fallback: `{"kind":"choice","answer":"human","unsure":true,"fallback":true,"confidence":0.6,"probabilities":{...}}`
- unsure verdict with fallback `No`: `{"kind":"verdict","answer":"No","unsure":true,"fallback":true,"verdict":false,"confidence":0.6,"probabilities":{"Yes":0.8,"No":0.2}}`

## Remote errors

9. `PlainOutput` gains:

```swift
    /// The line for a question on a run the model server failed, when every
    /// question has a fallback: `[name=]fallback` and nothing after it,
    /// because there are no numbers, even with `--stats`.
    public static func fallbackLine(for question: Question) -> String
```

10. `JSONOutput` gains:

```swift
    /// The line for a run the model server failed, when every question has
    /// a fallback: each object has `kind`, `answer` (the fallback), and
    /// `"fallback": true`, and a verdict adds `verdict`; no `score`,
    /// `confidence`, or `probabilities`, because there are no numbers. Keys
    /// and ids as `line(for:outcomes:)` gives them.
    public static func fallbackLine(for questions: [Question]) -> String
```

Ids are `name` or `q<N>`; make `Runner.identifier(for:at:)` internal and use it, so the two lines agree. Shape: `{"team":{"kind":"choice","answer":"human","fallback":true},"q2":{"kind":"verdict","answer":"no","fallback":true,"verdict":false}}` plus the newline.

11. `Decide.run`, in the `catch` around `Runner.decide`: print the message as today; when `ExitCode.code(for: error) == ExitCode.remote` and every question has a fallback, print the fallback lines (nothing with `--quiet`, the JSON line with `--json`, else one plain line per question) and return the decided code for the fallbacks; otherwise return the code as today. A setup error never takes a fallback.

12. `Decide.run`, after the lines print on the normal path: compute `printed = zip(questions, outcomes).map(Runner.printedAnswer)`; print `Unsure.report` when `unsureQuestions` is not empty; return `ExitCode.unsure` when any outcome is unsure and its question has no fallback; else the decided code. `exitCode(for:questions:)` becomes `exitCode(for printed: [String?], questions: [Question]) -> Int32`: one yes/no question exits 0 when its printed answer is the yes value and 1 otherwise; any other run exits 0. The `run` doc comment gains, after the sentence wip/a0g added: "A question's `--fallback` prints instead of an unsure answer and counts as decided. When the model server fails and every question has a fallback, the fallbacks print and the run is decided; otherwise nothing prints and the code is 11."

13. Usage text, after the `--min-confidence` entry:

```
          --fallback <value>             What this question prints when its answer is below
                                         its bar, or when the model server fails. A yes/no
                                         question's fallback is its --yes or --no value.
```

## Docs

14. README, the whole "## Errors" section becomes:

````
## Errors

```sh
# Handle non-decision errors (loss of network, etc.) using `--fallback`
$ sudo ip link set eth0 down
$ decide --context "$body" \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
         --min-confidence 0.7 \
         --fallback human

stderr>  Error: cannot reach decision model server
human

# A fallback also stands in for an answer below its bar, and the run is decided
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --name team \
         --option shipping \
         --option billing \
         --option returns \
         --min-confidence 0.95 \
         --fallback human \
         "Should we issue a refund?" \
         --name refund
team=human
refund=Yes

stderr>  Unsure: question 1 ("Which team handles this ticket?") has confidence 0.91, below the bar of 0.95
$ echo $?
0

# Define a safe path for a script; a yes/no fallback is its yes or no value
if decide --context "$body" "Is this message spam?" -q --fallback no; then
  mv "$file" spam/     # never reached on an error
fi
```

`--fallback` on a question names what it prints when its answer is below its `--min-confidence` bar, or when the run has a remote error. A question that prints its fallback counts as decided. A remote error prints every fallback when every question has one; when any question has none, nothing prints and the run exits 11. A setup error never takes a fallback.
````

15. README, "### Exit codes": the paragraph that starts "`--fallback` turns an unsure answer" becomes:

```
`--fallback` on a question makes an unsure answer a decision, and a remote error too when every question has one. With one yes/no question the fallback is its yes or no value, and the code follows that side.
```

16. README, the `triage.json` example under "### Question files": the refund question gains `"fallback": "No"` after its `"min-confidence": 0.7` line (add the comma). Its output line stays `refund=Yes`.

## Tests

17. `CommandLineParserTests`: `--fallback human` on a choice sets `fallback`; the `=` form; on a rating; on a yes/no question with default sides `yes` and `no` pass and `maybe` throws its message; with `--yes spam --no ham`, `ham` passes and `no` throws; `--fallback no` before `--yes spam --no ham` throws (the check runs on the final sides); repeated, empty, and tabbed values throw their messages; before any question and after a `.questions` item throw `lastBuilder`'s messages; `-q` with `--fallback no` parses.

18. `QuestionFileTests`: a text file holding `--fallback human` after a question splices it (it is a value flag). `JSONQuestionFileTests`: `"fallback": "human"` decodes onto the question; empty, tabbed, and a non-side value on a yes/no question refuse with `questions[0].fallback: <problem>`; a number is `questions[0].fallback: expected a string`.

19. `PlainOutputTests`: an unsure choice with a fallback prints `team=human`, with `.stats` the model's fields follow; `fallbackLine` prints `team=human` for a named question and `human` for an unnamed one, with no fields even at `.distribution`.

20. `JSONOutputTests`: the two shapes in item 8; `fallbackLine` for a named choice and an unnamed verdict gives the shape in item 10; a sure line is unchanged.

21. `DecideRunTests`, scripted model: the README's second Errors example (bar 0.95, fallback human) prints `team=human\nrefund=Yes\n`, the `Unsure:` line for question 1 at 0.91 and 0.95, exit 0; the same without the fallback prints `team=\nrefund=Yes\n`, exit 2; a yes/no question below its bar with `--fallback no` prints `no` and exits 1, with `--fallback yes` prints `yes` and exits 0, and with `-q --fallback no` prints nothing and exits 1; `--json` on the unsure-with-fallback batch; a `ScriptedModel { _ in throw DecisionError.timeout }` with every question carrying a fallback prints the fallback lines, `Error: the request timed out.` on stderr, and exits 0, and with one yes/no question `--fallback no` exits 1; the same batch with one question lacking a fallback prints nothing and exits 11 (`timeout` stays as it is); `--json` on the remote path gives the item 10 shape; a `ScriptedModel { _ in throw DecisionError.unauthorized }` with fallbacks prints nothing and exits 10; the usage text lists `--fallback`.

## Out of scope

Streaming and `--each`. A run-wide fallback. Fallbacks for setup errors. Retrying. The library. No live test.

---

_📝 Noted on 2026-09-24 03:55:58-04:00 @ git:a2d24c9+local_

Implementation (2026-09-24), worker's calls accepted on review: (1) Two test copies of the README's triage.json (QuestionFileTests.readmeTriageJSON, JSONQuestionFileTests.triage) gained "fallback": "No" to stay byte-for-byte with the README; DecideRunTests.jsonFileUnsure now expects refund=No and exit 0 with the Unsure: line. (2) PlainOutput.fallbackLine and JSONOutput.fallbackLine print an empty or null answer for a question with no fallback rather than trap; Decide.run calls them only when every question has one. (3) Private helpers: PlainOutput.prefix(_:), JSONOutput.kind/answer/verdict shared by value and fallbackLine, JSONQuestionFile.QuestionBody.checkFallback, CommandLineParser.setFallback. (4) Runner.identifier(for:at:) is internal for JSONOutput.fallbackLine. Main-context fixes after hand-back: the README's second Errors example printed refund=Yes in the design record but the bare refund question has default sides, so the README line is refund=yes (the tests already asserted that); DecideLiveTests.triagesFromAJSONFile now expects exit 0 either way, refund=Yes or refund=No with empty stderr, or refund=No with an Unsure: question 3 line, since the file's refund carries a fallback; Outcome.unsure's doc says the line prints its fallback or no answer and the run exits 2 only without one; one over-long doc line in the parse comment rewrapped. Nothing committed yet.

---

_📝 Noted on 2026-09-24 03:59:43-04:00 @ git:a2d24c9+local_

Summary (2026-09-24): done. --fallback after a question and "fallback" in a JSON question file name what an unsure question prints; a yes/no fallback must be a side, checked on the final sides on both surfaces. Runner.printedAnswer(for:outcome:) gives the printed answer to both printers and the exit code. A remote error prints every fallback (PlainOutput.fallbackLine, JSONOutput.fallbackLine, no numbers) and exits as decided when every question has one, else nothing and 11; a setup error takes none. The Unsure: line prints whenever a question is below its bar; exit 2 only when one has no fallback. Usage text, README Errors section and Exit codes paragraph, and the triage.json example updated. Verifier: all six criteria hold, no blockers; its two coverage notes led to timeoutWithVerdictFallback covering both sides and quietTimeoutWithVerdictFallback (-q, timeout, --fallback no: empty stdout, exit 1). 504 offline tests and 5 live tests pass.
