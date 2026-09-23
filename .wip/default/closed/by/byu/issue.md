---
priority: p2
type: feature
created: 2026-09-23T01:35:01-04:00
updated: 2026-09-23T04:29:25-04:00
blocked-on:
  - g3q
---

# --name <identifier>: name a command-line question

# --name <identifier>: name a command-line question

## Objective

`decide --context @ticket.txt "Which team handles this ticket?" --name team --option shipping --option billing --option returns` runs the question under the name `team`: the library's spec id is `team`, so the model sees it, messages use it, and the later `--json` output keys by it. Plain output is unchanged, one answer per line. A name is an identifier, is given at most once per question, and is unique across the run, JSON-file questions included.

## Context

Requested by the user on 2026-09-23, after weighing `--name` against `--id`, `--as`, `--label`, and `--key`. `--name` matches the JSON question file's key (wip/5r7): a question has a name, an option or level or side has an id, and the command line keeps the two words apart. There is no parser conflict with `--option name`: a flag's value is always the next token or the text after `=`, so a bare `name` is only ever a value.

Blocked on wip/g3q, which adds `Question.name` and makes `Runner.makeQuestionnaire` use it as the spec id (`name ?? "q<N>"`). This issue is the command-line way to set that field. wip/rqr (JSON splice) will append named questions from files; the run-wide uniqueness check built here covers those too, so rqr reuses it.

Today's per-question flags in `CommandLineParser` are `--option`, `--level`, `--yes`, `--no`, and `--min-confidence`; `--min-confidence` is the model: `setMinimumConfidence(_:to:)` sets a field on the last `QuestionBuilder`, refuses a repeat, and validates the value. wip/qc4's amendment lets a question file hold "questions and their flags"; `--name` is a question flag, so it is allowed in a text question file once this lands (update qc4's allowed list if this lands first, or add it there if qc4 lands first).

## Location

- `Sources/DecideCore/CommandLineParser.swift`: the flag, the builder field, the run-wide check, the doc comment.
- `Sources/DecideCore/Decide.swift`: the usage text.
- `README.md`: one example.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `DecideRunTests.swift`.

## Approach

**Parser.** `--name <value>` and `--name=<value>` through `flagValue`, handled in the main loop beside `--min-confidence` with a `setName(_:to:)` that mirrors `setMinimumConfidence`: before any question → `--name before any question`; already set → `question N ("...") repeats --name`; not an identifier (a letter or `_` then letters, digits, or `_`, ASCII, non-empty) → `question N ("...") has an invalid name "x": a letter or _ then letters, digits, or _`. `QuestionBuilder` gains `var name: String?` and passes it to `Question(name:)`. After `finished` is built (and, once wip/qc4 lands, after `.questions` items are appended in `parse(items:)`), a run-wide check: a name that appears on two questions throws `question name "team" is used twice`. Put the identifier rule in one internal helper, `isIdentifier(_:)`, so wip/ndr's context names and wip/hah's JSON names can share it; whichever of the three lands first adds it. The `parse` doc comment gains: "`--name` after a question gives it a name, an identifier that is unique in the run."

**No other code path changes.** `Question.name` flows through g3q's `makeQuestionnaire` to the spec id and back through `Outcome.questionID`. The unsure message keeps `question N ("instructions")`, which is stable whether or not a question is named.

**Usage text**, after the `--min-confidence` entry, in the current column:

```
  --name <name>                  The question's name, an identifier. It is the id the
                                 question runs under. Default: q1, q2, and so on.
```

**README**, in the Usage block after the batch example (the user may move it):

```sh
# Name questions; the name is the id each runs under
$ decide --context @ticket.txt \
     "Which team handles this ticket?" --name team \
         --option shipping --option billing --option returns \
     "Should we issue a refund?" --name refund
returns
yes
```

## Tests

- Parser: both value forms give `Question(..., name: "team")`; `--name` before any question; `--name` twice on one question; invalid names `1st`, `a-b`, `a b`, and empty, each with the message; two questions with the same name throw the used-twice message and two with different names parse; `--name` on a question with `--option`s, with `--level`s, and on a bare yes/no question; `-q` with one named yes/no question is allowed.
- Run level: the README team question with `--name team` and a scripted model whose record is keyed `team` prints `returns\n`, exit 0, and the recorded request's one spec has id `team`; the same line with a model keyed `q1` exits 11 with the malformed-response message naming `team`, which proves the id reached the request; two questions named alike exit 10 with the usage text and nothing on stdout.
- No live test: only the spec id changes, and the library's own live tests already run arbitrary ids (TESTING.md).

## Related Issues

Blocked on wip/g3q. Shares the identifier rule with wip/ndr and wip/hah, and the run-wide name check with wip/rqr; wip/qc4's allowed-flag list gains `--name`. `--json` output, which makes names visible, is unfiled.

## Acceptance Criteria

- [ ] `--name <identifier>` after a question sets its name, in both value forms, and the request's spec id is that name.
- [ ] Before any question, twice on one question, an invalid name, and a name used twice in the run each exit 10 with the message above and nothing on stdout.
- [ ] `--help` and the README show the flag.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-23 03:59:52-04:00 @ git:40ae06a+local_

Design record (2026-09-23), the decisions the Approach left open. Implemented as written there, plus:
1. The identifier rule already exists: wip/ndr added CommandLineParser.isName(_:) for context names. It is renamed isIdentifier(_:) and made internal (no `private`) so wip/hah's JSON decoder can call it from its own file; the context-name path calls it by the new name. The rule and the message wording ("a letter or _ then letters, digits, or _") are unchanged.
2. setName(_:to:) mirrors setMinimumConfidence: last question, once, valid. Its messages, verbatim: `--name before any question`; `question N ("...") repeats --name`; `question N ("...") has an invalid name "x": a letter or _ then letters, digits, or _`. An empty value (`--name=`) is an invalid name with an empty string in the quotes, not a separate message.
3. The run-wide check is a private static func uniqueNames(_ questions: [Question]) throws(UsageError), called right after `finished` is built and before the --show-names/--quiet checks. The first name seen on two questions throws `question name "team" is used twice`. wip/rqr will call the same function after splicing file questions in.
4. Question.name's doc (from g3q) says what a name is for, not where it comes from, so no doc change there.
5. wip/g3q landed first and made the spec id `name ?? "q<N>"`, so --name flows to the request with no Runner change.
6. wip/qc4 (text question files) has not landed: its allowed-flag list gains --name when it does; noted here for qc4.
7. The README example goes after the batch example's output (`yes`) and before "# Compose context from multiple sources", inside the same code block, blank line each side.

---

_📝 Noted on 2026-09-23 04:12:44-04:00 @ git:729dd1b+local_

Design record, addendum (2026-09-23), from wip/g3q's verification:
8. QuestionBuilder already has a method name(_ number:) that renders `question N ("...")` for messages. It is renamed label(_:) so the builder can hold a stored `name: String?`; every caller in the file follows.
9. A name that equals another question's positional id (question 1 named "q2" beside an unnamed question 2) is not a parser error: the library's preflight refuses two specs with one id, and decide reports it as exit 10 with `Error: invalid question q2: Two questions share the id.` A run test pins that, so the behaviour is deliberate.
10. The unsure message keeps `question N ("instructions")` by position, as the Approach says.
11. --show-names already prints outcome.questionID, so a run test here pins `team=returns` for a named question; wip/3tz left that test to this issue.

---

_📝 Noted on 2026-09-23 04:19:56-04:00 @ git:729dd1b+local_

Implementation (2026-09-23): a worker implemented the Approach and both design-record notes as written; no open question came up. Beyond the record:
- The run-wide check is named checkUniqueNames (the record said uniqueNames) and is called right after `finished` is built, before the context check and the --show-names/--quiet checks; the record's item 3 said "before the --show-names/--quiet checks", which still holds.
- DecideRunTests gained namedTeamQuestion (the team question with --name team) and namedTeamModel(recording:), a scripted model keyed by "team", mirroring triageModel(recording:).
- Both exact-message run tests matched on the first run: `Error: the model's response is malformed: The response holds no answer for team.` (exit 11) and `Error: invalid question q2: Two questions share the id.` (exit 10).
Checks: warnings-as-errors build clean; `swift test --skip DecideLive` 301 tests in 8 suites pass.
Noted for wip/qc4: its allowed-flag list for text question files gains --name.

---

_📝 Noted on 2026-09-23 04:28:24-04:00 @ git:729dd1b+local_

Summary (2026-09-23): done. --name <identifier> after a question sets Question.name through setName(_:to:) on the builder; checkUniqueNames refuses a name on two questions; isName became the internal isIdentifier shared by context names; the builder's message helper is label(_:). The spec id is the name, so the model sees it and --show-names prints it. Usage and the README Usage example added.
Verifier: all four acceptance criteria hold, no blockers; it ran the README example and a four-question mix of named and unnamed questions live: output stays in question order and an unnamed fourth question keeps q4. Acted on three coverage notes: showNamesNamedQuestion now asserts empty stderr; a `--name` last-token test; the `--name=` empty form pinned. Left: the usage test checks only the first --name line, as its siblings do.
Final: warnings-as-errors build clean; `swift test` with .env sourced, 307 tests in 9 suites passed, live included.

---

_📝 Noted on 2026-09-23 04:29:25-04:00 @ git:451f719_

Correction: the final run was 306 tests in 9 suites, not 307.
