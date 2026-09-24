---
priority: p2
type: task
created: 2026-09-23T23:36:33-04:00
updated: 2026-09-23T23:36:43-04:00
may-unblock:
  - mb3
---

# --name prints its question as name=answer; --show-names goes away

## Objective

A named question prints its line as `name=answer`; an unnamed question prints its answer alone, as today. `decide "Which team handles this ticket?" --name team --option shipping --option billing --option returns "Should we issue a refund?"` prints `team=returns` then `yes`. The `--show-names` flag goes away, with its two conflict checks and `Invocation.showNames`. Everything else about a plain run stays: the order, the exit codes, the empty stdout on exit 2 and above, and the exit code of a run with one yes/no question.

## Context

Decided with the user on 2026-09-23; the parent issue wip/1cy holds the record. The name is the question's id everywhere it appears: on the wire, as the `--json` key, and now at the head of its line. That is one idea in place of two flags. An unnamed question's position label `q<N>` carries nothing its line number does not, since every question prints exactly one line in question order, so it never prints. `--show-names` (wip/3tz) landed after the 0.2.0 tag and is unreleased, so this is a swap, not a break.

The mixed output is unambiguous. An id from the command line never holds `=`, because `--option`, `--level`, `--yes`, and `--no` split their value at the first one (`CommandLineParser.option(from:as:)`), and a name is an identifier. So a line with `=` is a named line, and `grep '^team='` never hits a bare answer. A script that wants a named question's bare answer strips the name with `cut -d= -f2-`.

`--name` with `--quiet` is fine: nothing prints. `--name` with `--json` is what it was: the key.

## Location

- `Sources/DecideCore/Invocation.swift`: remove `showNames` and its initializer parameter.
- `Sources/DecideCore/CommandLineParser.swift`: remove the `--show-names` token, the checks `--show-names does not go with --quiet` and `--show-names does not go with --json`, and the doc-comment sentences. `--show-names` becomes `unknown flag: --show-names`.
- `Sources/DecideCore/Decide.swift`: the print loop and the usage text.
- `README.md`: the Usage section's `--name` example, the Scripting section's `--show-names` example, and the JSON question file example's plain output.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `InvocationTests.swift`, `DecideRunTests.swift`.

## Approach

**Print loop.** `Decide.run` pairs each outcome with its question, `zip(invocation.questions, outcomes)`, and prints `(question.name.map { "\($0)=" } ?? "") + outcome.answer`. The sibling issue wip/mb3 moves this into a `PlainOutput` formatter; keep the change here to that one expression so wip/mb3 has one place to grow.

**Parser and Invocation.** Delete, do not deprecate: the flag never shipped. `Invocation.init` loses `showNames:` and every call site in tests drops it. The `parse` doc comment loses its `--show-names` sentence; the `--name` sentence gains "and its line prints as name=answer". The `--json` doc line loses "or `--show-names`".

**Usage text.** Remove the `--show-names` entry. The `--name` entry becomes:

```
  --name <name>                  The question's name, an identifier: its id on the wire
                                 and in --json, and its line prints as name=answer.
```

and `--json`'s "Not with --quiet or --show-names." becomes "Not with --quiet."

**README.** The Usage section's example with `--name team` and `--name refund` changes its output to `team=returns` and `refund=yes`, and its comment to "Name questions; a named question prints as name=answer". Under Scripting, the `--show-names` example becomes:

```sh
# A named question prints as name=answer; an unnamed one prints its answer alone
$ decide --context @ticket.txt \
         "Which team handles this ticket?" --name team \
             --option shipping --option billing --option returns \
         "Should we issue a refund?"
team=returns
yes
```

The JSON question file example's plain output becomes `team=returns`, `urgency=somewhat_urgent`, `refund=Yes`.

## Tests

- Parser: `--show-names` is `unknown flag: --show-names`. The `showNamesAnywhere`, `showNamesTwice`, `showNamesWithQuiet`, `showNamesConflictComesFirst`, and `showNamesAlone` tests go, as do the `--json` with `--show-names` conflict tests; `Invocation` equality tests drop the field.
- Run, with the scripted triage model: the Scripting example prints `team=returns\nyes\n`; the batch with all three questions named prints `team=returns\nurgency=somewhat_urgent\nrefund=yes\n`; a mix of named and unnamed questions keeps every line in question order with no `q<N>` anywhere; a named yes/no question prints `refund=no` and exits 1; a named question under its bar prints nothing and exits 2; `--name refund -q` on a yes/no question prints nothing; `--json` with a named question is unchanged. The `showNames*` run tests are replaced, not kept. `usageListsShowNames` becomes a test that `--help` no longer mentions the flag and that the `--name` line says `name=answer`.
- No live test: the wire does not change (TESTING.md).

## Related Issues

Parent wip/1cy. wip/3tz added the flag; wip/byu added `--name`; wip/4qk's `--json` conflict check goes. wip/mb3 builds on this print loop and is blocked on it. wip/qc4's coordination note about `--name` in a text file stands.

## Acceptance Criteria

- [ ] A named question prints `name=answer`, an unnamed one its answer alone, in question order; exit codes are unchanged.
- [ ] `--show-names` is an unknown flag; `Invocation` has no `showNames`.
- [ ] `--help` and the README show the new `--name` behaviour and no `--show-names`.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.
