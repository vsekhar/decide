---
priority: p3
type: task
created: 2026-09-27T14:15:46-04:00
updated: 2026-09-27T15:15:10-04:00
blocked-on:
  - bpg
---

# Unnamed --context-json: skip the name attempt for a value that starts with {, [, or "

## Objective

Decide whether an unnamed `--context-json` value that starts like JSON should skip the name attempt, so `--context-json '{"a":"x=y"}'` parses as JSON instead of failing as a bad name.

## Context

Found on 2026-09-27 while building wip/bpg. `--context-json` shares the value grammar of `--context`: the text before the first `=` is a name attempt when it is non-empty and holds no whitespace, and an invalid name is an error, not text. That rule catches typos like `1st=` and `ticket.id=`, and the parser test `invalidContextName` documents that a path or a URL before `=` is refused the same way. Compact JSON is the new case it bites: `--context-json '{"a":"x=y"}'` is refused as `--context-json name "{"a":"x" is not valid: a letter or _ then letters, digits, or _`. JSON with a space before the `=`, `@<path>`, and `-` all avoid it, and every named form is fine, so wip/bpg kept the grammar shared and logged this.

## Location

`Sources/DecideCore/CommandLineParser.swift`, `contextEntry(from:flag:format:)`; `Tests/DecideCoreTests/CommandLineParserTests.swift`.

## Approach

One option: for `--context-json` only, treat a value whose first scalar is `{`, `[`, or `"` as unnamed text before the name attempt runs, because a name starts with a letter or `_`, so such a value can never be a named context. A number, `true`, `false`, and `null` hold no `=`, so they are already fine. The change is one guard and a doc-comment sentence, plus tests for `{"a":"x=y"}`, `["x=y"]`, and `"x=y"`. Keep `--context` as it is: its rule and test stand.

Another option: leave it, and document the workaround in the usage text. Decide which before doing either.

## Acceptance Criteria

- [ ] A decision is logged: the guard is built and tested, or the usage text names the workaround.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes.

---

_📝 Noted on 2026-09-27 14:37:55-04:00 @ git:8c5fe99+local_

2026-09-27: recommendation put to the user with the cba questions: build the guard (a value whose first scalar is {, [, or " is unnamed text before the name attempt). The user answered the cba points and not this one yet, so it waits on a yes or no.

---

_📝 Noted on 2026-09-27 15:11:24-04:00 @ git:e6c3606+local_

2026-09-27: the user chose A after seeing examples: a --context-json value whose first character is {, [, or " skips the name attempt and is the text itself, because a name starts with a letter or _. --context keeps its rule. Implemented in the main context: one guard in contextEntry(from:flag:format:), a sentence on parse and contextEntry, parser tests for the three starts and for --context unchanged, and a run test case with base64 padding.

---

_📝 Noted on 2026-09-27 15:15:10-04:00 @ git:e6c3606+local_

Summary (2026-09-27): built option A in the main context. One guard at the top of contextEntry(from:flag:format:): under .json, a value whose first character is {, [, or " is .unnamed(.text(value), .json) before the = search. Two doc sentences. Tests: contextJSONStartsLikeJSON (four values, both spellings), contextStartsLikeJSON (--context keeps the name error), and a base64-padding case in unnamedContextJSON. Mutant killed: with the guard removed both tests fail. Verifier: no blockers; a BOM or combining mark before { does not match the guard and still gets the name error, which is fine; the @ and - paths are unchanged. 569 offline tests pass with warnings as errors; no live run, the wire does not change.
