---
priority: p2
type: task
created: 2026-09-24T02:48:53-04:00
updated: 2026-09-24T02:49:20-04:00
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
