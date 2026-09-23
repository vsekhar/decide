---
priority: p2
type: feature
created: 2026-09-23T01:42:50-04:00
updated: 2026-09-23T03:24:35-04:00
---

# --show-names: print each answer as name=answer

# --show-names: print each answer as name=answer

## Objective

`decide --context @ticket.txt "Which team?" --option shipping --option billing --option returns "Should we issue a refund?" --show-names` prints `q1=returns` and `q2=yes`, one line per question, the question's name before an `=` and the answer after it. A named question (wip/byu, or a JSON file's `name`) prints its name; an unnamed one prints its position label, `q1`, `q2`, and so on. Everything else about a plain run stays the same: the order, the exit codes, and the empty stdout on exit 2 and above. `--show-names` with `--quiet` is a usage error, and with `--json` once that exists.

## Context

Requested by the user on 2026-09-23. Decided the same day: the flag is `--show-names`, the separator is `=` so a shell can split each line at its first `=`, and the flag is only for plain output, so combining it with `-q` or `--json` is an error rather than an override. A name is an identifier and never holds `=`; an answer may (`--yes "a=b"` prints `refund=a=b`), and a split at the first `=` still gives the name.

Today `Decide.run` prints `outcome.answer` per line, and `Outcome.questionID` already holds the spec id, `q<N>` by position (`Runner.identifier(at:)`). wip/g3q makes that id the question's name when one is set, and wip/byu sets it from the command line; this issue needs neither, and prints whatever id the outcome carries. `--quiet` is the model for a run-wide bare flag: `Invocation.quiet`, taken once, checked after the questions are built.

## Location

- `Sources/DecideCore/Invocation.swift`: `showNames`.
- `Sources/DecideCore/CommandLineParser.swift`: the flag and the `--quiet` check.
- `Sources/DecideCore/Decide.swift`: the print loop; the usage text.
- `README.md`: one example under Scripting.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `DecideRunTests.swift`.

## Approach

**Invocation.** `public var showNames: Bool`, doc comment "Print each answer as `name=answer`, from `--show-names`. Never with `quiet`." Initializer: `showNames: Bool = false` after `quiet` (before the `model` and `apiKey` parameters wip/79i adds, if that has landed; order the defaults so every existing call compiles).

**Parser.** `--show-names` anywhere on the line, a bare flag handled beside `--quiet`: a second one throws `--show-names was given twice`. After the questions are built, `quiet && showNames` throws `--show-names does not go with --quiet`; the `--quiet` one-yes/no-question check stays as it is. `--set-config` lines are unchanged (the pre-scan throws "runs alone"). The `parse` doc comment gains: "`--show-names` prints each answer with its question's name, and does not go with `--quiet`."

**Run.** In the print loop, `showNames ? "\(outcome.questionID)=\(outcome.answer)" : outcome.answer`. Nothing else: the exit-code rule for one yes/no question still reads the answer, and an unsure or failed run still prints nothing.

**`--json`.** When the `--json` output flag is filed, its parser check adds `--show-names does not go with --json`. Record this in that issue; nothing here.

**Usage text**, after the `--quiet, -q` entry, in the current column:

```
  --show-names                   Print each answer as name=answer, the name from
                                 --name or q1, q2, and so on. Not with --quiet.
```

**README**, under Scripting after the `--json` example:

```sh
# Print each answer with its question's name (from --name, or q1, q2, ...)
$ decide --context @ticket.txt \
         "Which team handles this ticket?" --name team \
             --option shipping --option billing --option returns \
         "Should we issue a refund?" \
         --show-names
team=returns
q2=yes
```

The example uses `--name` from wip/byu; the README shows the spec, and the run test below uses the position labels, which exist today.

## Tests

- Parser: `--show-names` before the context, between questions, and last, each giving `showNames == true` and the same questions; twice; `--show-names -q` and `-q --show-names` and `--quiet --show-names` each throwing the does-not-go message; `--show-names` alone with no question still throws `no question given`.
- Run level with the scripted triage model: the batch example with `--show-names` prints `q1=returns\nq2=somewhat_urgent\nq3=Yes\n`, exit 0; a bare yes/no question with `--show-names` prints `q1=no\n` and exits 1 (the exit-code rule survives); a run whose refund is below its bar prints nothing and exits 2; `--show-names -q` exits 10 with the usage text and nothing on stdout; once wip/g3q and wip/byu have landed, a named question prints `team=returns` (add the test then, or now if they are in).
- No live test: the wire does not change (TESTING.md).

## Related Issues

wip/byu (`--name`) and wip/g3q (names as ids) give the labels their real values; neither blocks this. The unfiled `--json` output issue adds the `--json` conflict check. wip/79i and wip/ndr also touch `Invocation.init`; land one at a time.

## Acceptance Criteria

- [ ] `--show-names` prints `name=answer` per line, with `q<N>` for unnamed questions, in question order; exit codes are unchanged.
- [ ] `--show-names` twice, or with `-q` or `--quiet`, exits 10 with the message and nothing on stdout.
- [ ] `--help` and the README show the flag.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-23 02:00:34-04:00 @ git:55cbb66+local_

Coordination 2026-09-23: --json is filed as 4qk. The check "--show-names does not go with --json" goes in whichever of 3tz and 4qk lands second, since the first cannot name a flag that does not exist yet.

---

_📝 Noted on 2026-09-23 02:59:29-04:00 @ git:1e11d31+local_

Design record (2026-09-23), the decisions the Approach left open. Implemented as written there, plus:
1. Order of the post-question checks in parse: the conflict check (`--show-names does not go with --quiet`) runs before the existing `--quiet needs exactly one yes/no question` check, because the pair is wrong whatever the questions are.
2. Invocation.init parameter order: context, questions, quiet, showNames, model, apiKey; the last three defaulted (wip/79i landed first and added model and apiKey).
3. The README example under Scripting goes right after the --json example and before "Branch in a script via exit codes", as the issue says; it uses --name from wip/byu, which is not built yet, so the README shows the spec and the run tests use q1, q2, q3.
4. No named-question run test yet: wip/g3q and wip/byu have not landed. Add it with them.
5. The --json conflict check is 4qk's, since 4qk lands after 3tz (per the coordination note).
6. No live test: the wire does not change.

---

_📝 Noted on 2026-09-23 03:18:31-04:00 @ git:27fbcf9+local_

Assumption corrected (2026-09-23): the Context paragraph says an answer may hold `=` (`--yes "a=b"` prints `refund=a=b`). It cannot, from the command line: option(from:as:) splits every --option, --level, --yes, and --no value at its first `=` into id and description, and the id is what prints, so `--yes "a=b"` prints `q1=a`. The existing test "--option id=a=b keeps the rest of the value as the description" pins that. The planned run test for an answer with `=` is dropped as unreachable. The split-at-first-`=` rule for readers still holds, since a name never holds `=`; an answer with `=` can only come from a JSON question file's id, which is later work (wip/g3q).

---

_📝 Noted on 2026-09-23 03:20:12-04:00 @ git:27fbcf9+local_

Implementation (2026-09-23): a worker implemented the Approach and the design record as written. It stopped once, on the `=`-in-answer test, which led to the assumption correction above; the test was dropped and nothing else changed. Beyond the record:
- The Invocation(...) call at the end of parse is one argument per line, and the ternary in Decide.run is wrapped over three lines, both for width.
- Test names are the worker's; the "anywhere" parser test loops over three lines with a comment per line, like quietNeedsOneVerdict.
- The unsure run test asserts only exit 2 and empty stdout; the existing unsureBatch test already pins the stderr text.
Checks: warnings-as-errors build clean; `swift test --skip DecideLive` 282 tests in 8 suites pass. No live test added; the wire is unchanged.

---

_📝 Noted on 2026-09-23 03:24:35-04:00 @ git:27fbcf9+local_

Summary (2026-09-23): done. --show-names is a bare run-wide flag beside --quiet: Invocation.showNames, taken once, a conflict error with --quiet checked before the one-question rule. Decide.run prints `questionID=answer` per line when set and is otherwise unchanged, so exit codes and the empty stdout on exit 2 and above hold. Usage lines and the README Scripting example added.
Verifier: all four acceptance criteria hold, no blockers, checked on the binary too (exit 0, 1, 2, and two exit-10 paths, stdout empty on every exit of 2 or more; a live 3-question batch prints q1, q2, q3 in command-line order). Notes, no action: `--show-names=x` is `unknown flag` by the generic check with no test, like `--quiet=x`; a line with both a context error and the flag pair reports the context error first, unspecified either way; the unsure run test leaves the stderr text to unsureBatch. Correction to the implementation note: the "anywhere" parser test passes "\(line)" as the #expect message, not a comment per line.
Open for later: a run test that a named question prints `team=returns`, once wip/g3q and wip/byu land; the `--show-names does not go with --json` check goes in wip/4qk.
Final: warnings-as-errors build clean; `swift test --skip DecideLive` 282 tests in 8 suites; the live suite 4 tests, all passed.
