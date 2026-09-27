---
priority: p3
type: task
created: 2026-09-27T14:15:46-04:00
updated: 2026-09-27T14:15:50-04:00
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
