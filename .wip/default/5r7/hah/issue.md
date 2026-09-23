---
priority: p2
type: task
created: 2026-09-23T01:25:20-04:00
updated: 2026-09-23T01:25:20-04:00
blocked-on:
  - g3q
may-unblock:
  - rqr
---

# Decode a JSON question file into questions, strictly, with a path in every message

# Decode a JSON question file into questions, strictly, with a path in every message

## Objective

A pure function turns the text of a JSON question file, in the README's schema, into `[Question]`, or throws a `ConfigError` naming the file and the JSON path of the problem (`questions[2].levels[1].id`). It accepts exactly the schema and refuses anything else, so a typo in a key is an error and not a silently ignored field.

## Context

Second child of the JSON question files parent; blocked on the model child (the `Question` and `Option` fields it fills). The README's second "Question files" example is the schema. `ConfigFile.parse` (wip/mia) set the pattern: a pure function, path only for messages, no value from the file in a message, strict acceptance.

## Location

- `Sources/DecideCore/QuestionFile.swift`: `questions(fromJSON:path:)` beside `tokens`.
- `Tests/DecideCoreTests/QuestionFileTests.swift`.

## Approach

`public static func questions(fromJSON text: String, path: String) throws(ConfigError) -> [Question]`. Decode with `JSONDecoder` into private `Decodable` structs that mirror the schema; then validate; then build `Question`s.

Schema, with the README's example as the reference:
- Top level: an object with one key, `questions`, an array with at least one element. Any other top-level key: `unknown key "x"`. A top-level array or scalar: `a question file is an object with a questions array`.
- Each question: `instructions` (required): a string, or an object with `question` (required string) and `rules` (optional array of strings), no other keys. `name` (optional): an identifier, a letter or `_` then letters, digits, or `_`; the same rule as a context name (wip/ndr). Exactly one kind: `options` (array of option objects, at least one) makes a choice; `levels` (array of level objects, at least two) makes a rating; neither makes a verdict, whose `yes` and `no` (each optional) are side objects. `options` or `levels` together with `yes` or `no`, or both `options` and `levels`, is `question <n> mixes options, levels, yes, or no`. `min-confidence` (optional): a number from 0 to 1. Any other key: `unknown key "x"`.
- Each option, level, or side object: `id` (required, non-empty string; for a verdict side it is the value printed, as `--yes <value>` is), `summary` (optional string; when absent the id serves, as on the command line), `not_for` (optional string), `examples` and `signals` (optional arrays of strings). Any other key: unknown. A repeated id within one question's options or levels is `question <n> repeats the option "x"` / `the level "x"`; `yes` and `no` with the same id is `question <n> uses the same value for yes and no`, the parser's wording.
- Names must be unique within the file: `question name "team" is used twice`. Names unique across a whole run are the splice child's job.

Messages: `ConfigError(path: path, line: 0, problem: "<json path>: <problem>")`, for example `questions[1].levels: a rating needs at least two levels` or `questions[0].options[2]: unknown key "sumary"`. Foundation's decoding errors give a coding path; render it as `questions[i].key`. A syntax error is `not valid JSON` plus Foundation's own description when it holds no file content (an offset is fine); no value from the file lands in a message. Line 0 keeps the message shape `Error: <path>: <problem>`.

Mapping to `Question`: `instructions` is the string or the object's `question`; `rules` is the object's `rules` or `[]`; `name`; `minimumConfidence` from `min-confidence`; options and levels become `Option(id:, description: summary, notFor:, examples:, signals:)`; a verdict's sides likewise, with `Option(id: "yes")` / `Option(id: "no")` when absent, as the parser defaults.

Unknown keys: decode each object into `[String: JSONValue]`-style dictionaries or use a custom `init(from:)` that lists allowed keys, so unknown keys are refused; a plain `Decodable` struct ignores them silently, which the strictness rule forbids.

## Tests

The README's `triage.json` decodes to the expected three `Question`s, pinned whole: `team` with three options carrying the summaries, `not_for`, `examples`, and `signals` as written; `urgency` with three levels, the last with signals; `refund` with instructions "Should we issue a refund?", the two rules, `Yes`/`No` sides with summaries, and `minimumConfidence` 0.7. Then one test per rule above: string instructions; missing instructions; unknown top-level key; top-level array; empty `questions`; unknown question key; `sumary` typo; options with levels; options with yes; one level; zero options; a repeated option id; yes and no with one id; a bad name (`1st`, `a-b`, empty); a repeated name; `min-confidence` of 1.5 and of `"0.7"` (a string); a side with only examples; invalid JSON syntax; an empty text.

Every accepted fixture is valid JSON by construction; the README's is the one that matters.

## Related Issues

Parent: JSON question files. Blocked on the model child. The splice child consumes this function.

## Acceptance Criteria

- [ ] The README's `triage.json` decodes to the three questions exactly.
- [ ] Every rule above is tested, each refusal names the path, the JSON path, and the construct, and no message holds a value from the file.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean and `swift test --skip DecideLive` passes.
