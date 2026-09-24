---
priority: p2
type: task
created: 2026-09-23T23:36:43-04:00
updated: 2026-09-23T23:43:47-04:00
blocked-on:
  - hcp
---

# --stats and --distribution: per-question tab fields with confidence, probability, score, and id:probability entries

## Objective

Two per-question flags add fields to a question's line after the `[name=]answer` head that wip/hcp prints. `--stats` adds one tab-separated field holding space-separated values: `confidence:<n> probability:<n>`, plus ` score:<n>` on a rating. `--distribution` adds what `--stats` adds, then one tab-separated field per option, level, or side, `id:<n>`, in declared order, a level as `id[<index>]:<n>`. Numbers print with three decimals. A question without the flags prints as today. With `<TAB>` standing for a tab:

```
$ decide --context @ticket.txt \
     "Which team handles this ticket?" --name team \
         --option shipping --option billing --option returns \
         --distribution \
     "How urgent is this ticket?" \
         --level not_urgent --level somewhat_urgent --level urgent \
         --stats \
     "Should we issue a refund?" --name refund
team=returns<TAB>confidence:0.910 probability:0.910<TAB>shipping:0.060<TAB>billing:0.030<TAB>returns:0.910
somewhat_urgent<TAB>confidence:0.780 probability:0.550 score:1.150
refund=yes
```

The numbers are the scripted triage model's, so this output and `--json` agree.

## Context

Decided with the user on 2026-09-23; the parent issue wip/1cy holds the record and the rejected forms. The short version:

- **Per question**, because users batch questions for latency and cost, and one routing question that needs its distribution should not widen every other line. The flags follow the question like `--min-confidence`. There is no run-wide form: `--stats` at the end of a line applies to the last question, as `--option` does, and a user who wants everything has `--json`.
- **One tab field for the stats**, so `cut -f2` is the stats field and `cut -d' ' -fN` a value within it: confidence first, probability second, score third when present.
- **One tab field per distribution entry**, so an id may hold spaces and colons, and `cut -f3-` is the whole distribution, `cut -f4` the second entry, `tr '\t' '\n'` one per line, `grep '^billing:'` one by name. Tab is the one character an id cannot hold.
- **`label:number` in every added field.** `=` marks the decision, `name=answer`; `:` marks a number with its label. A probability never holds a colon, so `${v##*:}` or `awk -F: '{print $NF}'` gives the number whatever the id holds.
- **The words are `--json`'s.** `confidence` is `Outcome.confidence`, the number `--min-confidence` tests. `probability` is `Outcome.probabilities[answer]`, the chosen option's, level's, or side's, so a no answer prints P(no). `score` is `Outcome.score`, the expected level index; levels count from 0 in declared order, which the brackets in the distribution show.
- **Three decimals, fixed width** (`%.3f`): `0.910`, `1.150`, `1.000`. Chosen over `--json`'s exact text for reading. The usage text says the bar tests the exact value.
- **`--json` implies both flags.** It prints every number for every question, so the flags add nothing under it and are not errors; a question file that asks for a distribution runs under `--json` unchanged. `--quiet` with either is an error, since nothing prints.
- **An id holds no tab or newline**; the parser refuses one. `=` is already impossible on the command line.

## Location

- `Sources/DecideCore/Invocation.swift`: `Question.Detail` and `Question.detail`.
- `Sources/DecideCore/CommandLineParser.swift`: the two flags; the id check in `option(from:as:)`; the `--quiet` conflict.
- `Sources/DecideCore/PlainOutput.swift` (new): the line formatter, pure, beside `JSONOutput`.
- `Sources/DecideCore/Decide.swift`: the print loop calls it; the usage text.
- `README.md`: the Scripting section.
- `Tests/DecideCoreTests/PlainOutputTests.swift` (new), `CommandLineParserTests.swift`, `InvocationTests.swift`, `DecideRunTests.swift`.

## Approach

**Model.** On `Question`: `public enum Detail: Sendable, Equatable { case answer, stats, distribution }` and `public var detail: Detail`, initializer parameter `detail: Detail = .answer` after `rules`. Doc comment: "What the question's line shows beyond its answer, from `--stats` and `--distribution`. `.distribution` includes `.stats`."

**Parser.** `--stats` and `--distribution` are bare per-question flags handled where `--min-confidence` is. Before any question: `--stats before any question`. The same flag twice on one question: `question 2 ("...") repeats --stats`. Both on one question is fine and gives `.distribution`; `QuestionBuilder` keeps `stats: Bool` and `distribution: Bool` and `question(number:)` maps them. After the questions are built, and before the one-yes/no-question rule where the old `--show-names` check sat, a question with `detail != .answer` under `quiet` throws `--distribution does not go with --quiet` when it asked for the distribution, else `--stats does not go with --quiet`. No `--json` check. `option(from:as:)` refuses an id holding a tab or newline with `an --option id holds a tab or newline`, worded per flag as `missingID` is. The `parse` doc comment gains two sentences.

**PlainOutput.** `public enum PlainOutput { public static func line(for question: Question, outcome: Outcome) -> String }`, no trailing newline; the caller prints. The head is `(question.name.map { "\($0)=" } ?? "") + outcome.answer`, moved here from `Decide.run`. Then by `question.detail`:
- `.stats` and `.distribution`: `"\t" + "confidence:" + number(outcome.confidence) + " probability:" + number(outcome.probabilities[outcome.answer] ?? 0)`, and when `question.kind` is `.rating` and `outcome.score` is set, `" score:" + number(score)`.
- `.distribution`: then, for the ids in declared order as `JSONOutput.probabilities` walks them (`options.map(\.id)`, `levels.map(\.id)`, `[yes.id, no.id]`), `"\t" + id + ":" + number(p)`; a level as `id + "[" + String(index) + "]:" + number(p)`. An id the outcome lacks reads 0, as in `JSONOutput`.

`number(_:)` is `String(format: "%.3f", value)`, locale-independent. Its doc comment says `--json` prints the exact value.

**Run.** The loop in `Decide.run` becomes `for (question, outcome) in zip(invocation.questions, outcomes) { print(PlainOutput.line(for: question, outcome: outcome), to: &stdout) }`.

**Usage text**, in the per-question group after `--name`:

```
  --stats                        Add a field to this question's line after a tab:
                                 confidence:<n> probability:<n>, and for a rating
                                 score:<n>, its expected level index. Levels count
                                 from 0 in declared order. Three decimals; the
                                 --min-confidence bar tests the exact value.
                                 Not with --quiet.
  --distribution                 --stats, then one field per option, level, or side
                                 as id:probability, in declared order; a level as
                                 id[index]:probability. Not with --quiet.
```

**README**, under Scripting after the `--name` example: the Objective's example (real tabs in the block), then the idioms:

```sh
# Fields are tab-separated; values inside the stats field are space-separated
$ decide ... --stats | cut -f2 | cut -d' ' -f1 | cut -d: -f2                          # confidence
$ decide ... --distribution | cut -f3- | tr '\t' '\n'                                    # one entry per line
$ decide ... --distribution | cut -f3- | tr '\t' '\n' | grep '^billing:' | cut -d: -f2   # one by name
```

and one paragraph: confidence is the number `--min-confidence` tests and probability is the chosen answer's, and on a yes/no question the two differ, `|2p - 1|` against P(side); for the whole distribution by name, `--json` and `jq` are the shorter path.

## Tests

- PlainOutput, pure, one outcome per kind with the scripted triage numbers: `.answer` gives the bare answer and `name=answer`; `.stats` on a choice, on a rating (with score), and on a verdict where a no answer's probability is P(no); `.distribution` on each kind, ids in declared order, levels bracketed from 0, a label with a space and one with a colon printed as they are; a missing id reads `0.000`; rounding: 0.6666 prints `0.667`, 1 prints `1.000`, 0.0004 prints `0.000`; no trailing newline.
- Parser: each flag after a question sets `detail`; before any question; twice on one question; both on one gives `.distribution`; on the second of two questions leaves the first `.answer`; with `-q` on the one yes/no question, each message; with `--json` it parses; an `--option`, `--level`, `--yes`, and `--no` id with a tab and with a newline, each refused; `Invocation` equality with `detail`.
- Run, scripted triage model: the Objective's example prints its three lines byte for byte, the expected string built with `\t`; `--distribution` on the refund question with `--yes "Hell yeah" --no "Forget it"` and the scripted P(yes) 0.87 prints `Hell yeah\tconfidence:0.740 probability:0.870\tHell yeah:0.870\tForget it:0.130`; `--json` with `--stats` prints the JSON line unchanged; `--stats -q` exits 10 with the usage text and nothing on stdout; a question under its bar prints nothing and exits 2.
- No live test: the wire does not change (TESTING.md).

## Related Issues

Parent wip/1cy. Blocked on wip/hcp, which prints the `name=` head and settles the print loop. wip/qsk (text question files) lists these flags as allowed in a file, and wip/hah (JSON question files) takes `stats` and `distribution` keys and refuses `=`, tab, and newline in an id; both were amended when this was filed, and neither blocks this. wip/4qk's `JSONOutput` is the model for the formatter and is untouched.

## Acceptance Criteria

- [ ] `--stats` and `--distribution` add exactly the fields above to their question's line and nothing to any other line; numbers have three decimals; exit codes are unchanged.
- [ ] Either flag before any question, twice on one question, or with `--quiet` exits 10 with the message and nothing on stdout; with `--json` the JSON line is unchanged.
- [ ] An id with a tab or newline is refused.
- [ ] `--help` and the README show both flags and the cut idioms.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-23 23:43:47-04:00 @ git:e1da41d+local_

Design record additions at start (2026-09-23), beyond the description: (1) option(from:as:) refuses an id holding a tab, a line feed, or a carriage return; the message says 'tab or newline'. (2) PlainOutput imports Foundation for String(format: "%.3f", value), which takes no locale and so always prints a dot. (3) TESTING.md's suite list gains PlainOutput. (4) Parser placement: the two bare flags are handled beside --min-confidence with the same 'before any question' and 'repeats' errors; the --quiet conflict check sits where the old --show-names/--quiet check sat, after the name and context checks and before the one-yes/no-question rule; a question that asked for both flags names --distribution in the message. (5) PlainOutput owns the whole line, head included, so Decide.run's loop is one call. (6) JSONOutputTests' fixtures (score 1.2) are the exemplar for PlainOutputTests; DecideRunTests' scripted model (score 1.15) drives the run tests, so the run-level expected strings use 1.150.
