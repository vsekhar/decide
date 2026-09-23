---
priority: p2
type: feature
created: 2026-09-23T02:00:34-04:00
updated: 2026-09-23T04:01:10-04:00
---

# --json: print the answers as one JSON object keyed by question name

# --json: print the answers as one JSON object keyed by question name

## Objective

`decide --context @ticket.txt "Which team handles this ticket?" --option shipping --option billing --option returns --json` prints one line, `{"q1":{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}}}`. Every run with `--json` prints one JSON object keyed by question name, in question order, whatever the count of questions; each value describes the answer by kind. Exit codes do not change. `--json` with `--quiet` or `--show-names` is a usage error.

## Context

Requested by the user on 2026-09-23, with these decisions the same day: always keyed, even for one question, so a script gets one shape (the README's single-question example changes to match); `answer` is the printed string for every kind; every kind has `confidence` and `probabilities`, so the chosen value's probability is `probabilities[answer]` whatever the kind; a kind-specific field appears on one kind only, `score` on a rating and `verdict` on a verdict, and a choice has none; and, from wip/3tz, `--show-names` and `--json` do not go together. An earlier draft had a boolean `answer` with a `label` field and a `probability` number on the verdict; the user replaced it with this vocabulary so that shared names mean one thing everywhere. The README's "Question files" and "Scripting" sections show the per-kind objects; the streaming example writes `--json` lines to a `.jsonl` file, which is why the output is one line.

Today `Decide.run` prints `outcome.answer` per line; `Outcome` holds `questionID`, `answer`, `confidence`, and `probabilities` keyed by option or level id (`Runner.swift`). `Outcome.questionID` is `q<N>` today and the question's name once wip/g3q and wip/byu land; this issue needs neither. The library's rating record carries a `score` (`AnswerRecord.rating(score:probabilities:confidence:)`), which `Outcome` drops today; the README shows it, so `Outcome` gains it here.

## Location

- `Sources/DecideCore/Runner.swift`: `Outcome.score`.
- `Sources/DecideCore/JSONOutput.swift` (new): the emitter.
- `Sources/DecideCore/Invocation.swift`, `CommandLineParser.swift`: the flag and its checks.
- `Sources/DecideCore/Decide.swift`: the print step; the usage text.
- `README.md`: the two `--json` examples.
- `Tests/DecideCoreTests/JSONOutputTests.swift` (new), `CommandLineParserTests.swift`, `DecideRunTests.swift`, `RunnerTests.swift`.

## Approach

**Outcome.** `public let score: Double?`, "The rating's expected level index from the model, nil for a choice or a verdict." `ratingOutcome` passes the record's score; the other two pass nil. The initializer gains `score: Double? = nil` last.

**Emitter.** `public enum JSONOutput { public static func line(for answers: [(question: Question, outcome: Outcome)]) -> String }`, pure, one line ending in `\n`. The object's keys are `outcome.questionID` in order. Each value, keys in this order:
- choice: `kind` `"choice"`, `answer` the chosen option id, `confidence`, `probabilities` an object keyed by option id in the question's declared option order.
- rating: `kind` `"rating"`, `answer` the chosen level id, `score`, `confidence`, `probabilities` keyed by level id in declared level order.
- verdict: `kind` `"verdict"`, `answer` the chosen side's id (the label plain output prints, `yes` or `no` by default), `verdict` `true` when that is the yes side's id else `false`, `confidence` (the library's two-way number, the one `--min-confidence` compares against), `probabilities` keyed by the yes side's id then the no side's, from `outcome.probabilities`. No `score` and no `probability`: the chosen value's probability is `probabilities[answer]`, as for the other kinds.

The vocabulary: `kind`, `answer`, `confidence`, and `probabilities` mean the same thing on every kind; `score` is the rating's expected level index and `verdict` the verdict's boolean, each on its kind only; a choice has no field of its own.

Strings are JSON-escaped (`"`, `\`, control characters; non-ASCII stays UTF-8; slashes unescaped); numbers print as JSON numbers the way `JSONEncoder` prints a `Double` (`0.91`, `1.2`, `0.3`). Build it with `JSONEncoder` and hand-written `Encodable` types that encode into keyed containers in the orders above, so the order is the encode order; no `.sortedKeys`. Object key order carries no meaning in JSON, but a stable order keeps the output diffable and the README exact.

**Flag.** `Invocation.json: Bool` ("Print the answers as one JSON object, from `--json`. Never with `quiet` or `showNames`"), initializer `json: Bool = false` beside `showNames`. Parser: `--json` anywhere, once (`--json was given twice`); after the questions are built, `json && quiet` throws `--json does not go with --quiet`, and `json && showNames` throws `--show-names does not go with --json` (if wip/3tz has not landed, this issue adds `showNames` handling only when it exists; the check goes in whichever of the two lands second). The `parse` doc comment gains a sentence.

**Run.** After the outcomes: `if invocation.json { print(JSONOutput.line(for: zip(...)), terminator: "") } else if !invocation.quiet { ...plain... }`. The exit-code rule and every error path stay: an unsure run still prints nothing on stdout and exits 2.

**Usage text**, after `--show-names` (or after `--quiet` if 3tz is not in), in the current column:

```
  --json                         Print one JSON object keyed by question name, with
                                 each answer's kind, confidence, and probabilities.
                                 Not with --quiet or --show-names.
```

**README.** In Scripting, the `--json` example's output becomes `{"q1":{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}}}`, and its comment gains "(one object keyed by question name; one line)". In Question files, the keyed example's `refund` value becomes `{"kind":"verdict","answer":"Yes","verdict":true,"confidence":0.74,"probabilities":{"Yes":0.87,"No":0.13}}` (its `yes` id is `Yes`, and 0.74 is the library's confidence at P(yes) 0.87), and the choice's `probabilities` object lists ids in declared order (`shipping`, `billing`, `returns`; the levels are already in order); a sentence below it says the tool prints the object on one line and the example is wrapped for reading.

## Tests

- Emitter: one test per kind pinning the exact string with the README's numbers; a run of three (the README's keyed example); an option id holding a quote, a backslash, a newline, and `é`; a verdict with custom labels keys `probabilities` by them, yes first, and `answer` is the label; with default labels the keys are `yes` and `no`; a no answer at P(yes) 0.2 gives `{"kind":"verdict","answer":"no","verdict":false,"confidence":0.6,"probabilities":{"yes":0.2,"no":0.8}}`; probabilities in declared order when the model reported them in another; `score` on a rating and absent elsewhere; `verdict` on a verdict and absent elsewhere; the line ends with one `\n`.
- Runner: a rating outcome carries the record's score; a choice and a verdict carry nil.
- Parser: `--json` anywhere; twice; with `-q`, `--quiet`, and `--show-names` (when present), each message; `--json` alone still gives `no question given`.
- Run level, scripted triage model: the batch with `--json` prints exactly the keyed three-question line with `q1`, `q2`, `q3`, its third value `{"kind":"verdict","answer":"Yes","verdict":true,"confidence":0.74,"probabilities":{"Yes":0.87,"No":0.13}}`, exit 0; a bare yes/no question with `--json` at P(yes) 0.2 prints `{"q1":{"kind":"verdict","answer":"no","verdict":false,"confidence":0.6,"probabilities":{"yes":0.2,"no":0.8}}}` and exits 1; an unsure run prints nothing and exits 2; `--json -q` exits 10 with the usage text and nothing on stdout.
- No live test: the wire does not change (TESTING.md).

## Related Issues

wip/3tz (`--show-names`) shares the conflict check; wip/byu and wip/g3q give the keys real names; wip/79i, wip/ndr, and wip/3tz also touch `Invocation.init`, so land one at a time. `--fallback` and streaming, which reuse this line format, are unfiled.

## Acceptance Criteria

- [ ] `--json` prints one line holding one object keyed by question id in question order, with the per-kind fields and key orders above, and the exit codes are unchanged.
- [ ] `answer` is the printed string for every kind; every kind has `confidence` and `probabilities`; `score` appears only on a rating and `verdict` only on a verdict.
- [ ] `--json` twice, or with `--quiet` or `--show-names`, exits 10 with the message and nothing on stdout.
- [ ] The README's two `--json` examples match the tool's output apart from line wrapping, and `--help` lists the flag.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-23 02:15:27-04:00 @ git:55cbb66+local_

Amended 2026-09-23 on the user's decision: answer is the printed string for every kind; every kind has confidence and probabilities (a verdict's keyed by its two labels, yes first); score is a rating's field only and verdict (the boolean) a verdict's field only; a choice has no field of its own. The earlier boolean answer, label, and probability fields are gone. The Emitter bullets, the README paragraph, the tests, and the acceptance criteria now say this.

---

_📝 Noted on 2026-09-23 04:01:10-04:00 @ git:40ae06a+local_

Design record (2026-09-23), the decisions the Approach left open, and one correction to it.

Correction. The Approach builds the line with JSONEncoder and hand-written Encodable types "so the order is the encode order". That premise fails: on this Mac (Apple Swift 6.4, macOS 27) an explicit keyed-container encode of six keys printed three different key orders in three runs, so JSONEncoder does not keep insertion order, and the README's exact output could not be pinned. JSONOutput therefore writes the JSON text itself: a private escape(_:) for strings and a private object(_:) that joins already-rendered key/value fragments in the order given. Strings: `"` and `\` escaped, `\n` `\r` `\t` as those two-character forms, every other control character below 0x20 as `\u00XX`, non-ASCII and `/` raw. Numbers: Double.description, the shortest round-trip form, which gives 0.74, 0.13, 0.6, 0.8, 0.91, 1.2, 0.3 for the README's values (checked: abs(2*0.87-1) prints 0.74, 1-0.87 prints 0.13, abs(2*0.2-1) prints 0.6). Every number the emitter prints is finite: the library keeps probabilities and confidence in 0...1 and the score is the model's finite number. Bools are `true`/`false`. No Foundation import is needed.

Decisions:
1. Choice probabilities are keyed by option id in the question's declared order; rating by level id in declared order; verdict by the yes side's id then the no side's. Values are outcome.probabilities[id] ?? 0 (the runner already fills absent ones at 0).
2. `verdict` is `outcome.answer == yes.id`. `answer` is outcome.answer for every kind.
3. Outcome.score is a Double? set by ratingOutcome from the record's score; the other two pass nil. The init parameter goes last with default nil.
4. Parser checks after the questions, in order: the name uniqueness check (byu), `--show-names does not go with --quiet` (3tz), `--json does not go with --quiet`, `--show-names does not go with --json`, then the --quiet one-question rule. `--json` twice is `--json was given twice`.
5. Decide.run: `if invocation.json { print(line, terminator: "") } else if !invocation.quiet { plain loop }`; the line carries its own newline. Every error path returns before it, unchanged.
6. wip/byu lands before this issue, so one run test names a question with --name and expects the key to be that name; the rest use q1, q2, q3.
7. The README's question-file --json example is the JSON file's own names (team, urgency, refund), which come from wip/rqr, not built yet; the README shows the spec, and this issue only corrects its field vocabulary and key order.
