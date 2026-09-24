---
priority: p2
type: feature
created: 2026-09-24T15:01:19-04:00
updated: 2026-09-24T15:01:19-04:00
may-unblock:
  - cba
---

# Add --context-json: a context whose value is parsed as JSON, so the model sees its structure

## Objective

`--context-json` is `--context` whose value is parsed as JSON, so the model sees the structure, not one string. `decide --context-json order='{"total": 45.00, "days_since_delivery": 12}' --context refund_policy=@refund_policy.txt "Should we issue a refund?"` sends the model `{"order": {"total": 45, "days_since_delivery": 12}, "refund_policy": "<the file's text>"}`. It takes every form `--context` takes: `<json>`, `@<path>`, `-`, and each with `<name>=` in front. A value that is not valid JSON exits 10 before any model call. The README's Streaming example writes `--context-json event=-`; this issue makes that flag exist, and wip/cba makes it stream.

## Context

Requested by the user on 2026-09-24 after a README audit found `--context-json` and `--each` unbuilt. The library's `State` (`DecisionModels/State.swift`) is `Codable` over every JSON value: `.text`, `.number`, `.bool`, `.null`, `.array`, `.object`. So `JSONDecoder().decode(State.self, from: Data(text.utf8))` turns any JSON text into the state the model sees, top-level scalars and arrays included.

How the code stands (HEAD 77f627e):

- `ContextSource` is `.text`, `.file`, `.standardInput`. `NamedContext` is a name and a source. `Context` is `.single(ContextSource)` or `.named([NamedContext])`, with `readsStandardInput`.
- `CommandLineParser.contextEntry(from:)` and `contextSource(from:as:)` read one `--context` value; the message prefix (`--context ` or `--context ticket=`) is a parameter of the second. `context(from:)` checks the line's values together: the mix rule, repeated names, then `-` twice.
- `Decide.loadState(_:standardInput:stderr:)` reads each source to text through `loadContext` and builds `.text` or `.object` of `.text`. A file that does not read prints `Error: cannot read context file "<path>": <reason>`; stdin prints `Error: cannot read standard input` or `Error: standard input is not valid UTF-8`; each returns nil, and the run exits 10 with no model call.
- `Decide.run`'s once-per-run check for `-` uses `Context.readsStandardInput`, and `QuestionFile.check` refuses every flag a question file may not hold, so `--context-json` in a file is refused as "not allowed" with no new code.
- Foundation's JSON syntax detail differs on Linux (no byte offset there), so no message here carries Foundation's text.

## Location

- `Sources/DecideCore/Invocation.swift`: `ContextFormat`, and the format on `NamedContext` and `.single`.
- `Sources/DecideCore/CommandLineParser.swift`: the flag, the shared value grammar, the line-wide checks.
- `Sources/DecideCore/Decide.swift`: the parse at load time, its messages, the usage text.
- `README.md`: one example under Usage.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `InvocationTests.swift`, `DecideRunTests.swift`, `QuestionFileTests.swift`.

## Approach

**Types.** Add `public enum ContextFormat: Sendable, Equatable { case text; case json }`: how the run turns a source's text into state, `.text` as one string, `.json` parsed. `NamedContext` gains `public let format: ContextFormat`, with `format: ContextFormat = .text` last in its init so every call site compiles. `Context.single` becomes `.single(ContextSource, ContextFormat)`; the few pattern matches in tests gain the second value. Doc comments say what each means, and that the model sees a JSON context as its parsed value, an object of named contexts holding parsed values beside text ones.

**Parser.** `--context-json <value>` and `--context-json=<value>` go through the same `contextEntry` and `contextSource` as `--context`, with the flag name passed in so every message names the flag the user typed: `--context-json name "1st" is not valid: ...`, `--context-json event= has no value`, `--context-json event=@ names no file`, `--context-json @ names no file`. Both flags append to the one `ContextEntry` list in command-line order, so the mix rule (`every --context needs a name when there is more than one, like --context ticket=@ticket.txt`, unchanged), the repeated-name rule (`--context names "event" twice`, unchanged, and it fires across the two flags), and the `-` once rule all apply as they do. The `parse` doc comment gains one sentence: "`--context-json` is `--context` whose value is parsed as JSON, in every form."

**Load.** `loadState` keeps reading each source to text through `loadContext`. For a `.json` format it then decodes: drop a leading BOM as `QuestionFile` does, then `JSONDecoder().decode(State.self, from: Data(text.utf8))`. On failure it prints `Error: context "<name>" is not valid JSON` for a named context and `Error: the context is not valid JSON` for an unnamed one, returns nil, and the run exits 10 with no model call; the message carries none of Foundation's text. Empty text is not valid JSON, so an empty file or empty stdin is that error. The state is the parsed value for `.single`, and for `.named` the object holds the parsed value under its name beside `.text` values from `--context`. Nothing in `Runner` or the wire changes: `State` already encodes every case.

**Usage text.** After the `--context <name>=-` line, in the current column:

```
          --context-json <json>          Context parsed as JSON, so the model sees its structure:
                                         objects, arrays, numbers, and booleans, not one string.
                                         Takes @<path> and - like --context.
          --context-json <name>=<json>   A named JSON context, in the same three forms.
```

**README.** Under Usage, after the "Compose context from multiple sources" example:

```sh
# Give the model structured context; --context-json parses its value as JSON
$ decide --context-json order='{"total": 45.00, "days_since_delivery": 12}' \
         --context refund_policy=@refund_policy.txt \
         "Should we issue a refund?"
yes
```

## Out of Scope

- `--each` (wip/cba): reading events line by line.
- A JSON schema or shape check on the value: any valid JSON goes through.
- Merging a JSON object's keys into the top level: a named JSON context is one field, like every named context.

## Tests

- Parser: each of the six forms gives the right `Context` with `.json`; `--context` alone still gives `.text`; the four messages above name `--context-json`; `--context ticket=@t --context-json ticket=@e` is the repeated-name error; `--context-json @e --context policy=@p` is the mix error; `--context-json event=- --context ticket=-` is the `-` twice error; `--context-json` with no value is `--context-json needs a value`.
- Question files: a text file holding `--context-json x=y` is refused as not allowed.
- Run (scripted model, `RequestBox`): the README example sends `.object(["order": .object(["total": .number(45), "days_since_delivery": .number(12)]), "refund_policy": .text(...)])`; an unnamed `--context-json '[1, 2, 3]'` sends `.array`; an unnamed `--context-json '"just text"'` sends `.text`; a file and stdin (`ScriptedInput`) each parse; a value that is not JSON, an empty file, and empty stdin each exit 10 with the message and no model call; a BOM-prefixed file parses; the once-per-run check still fires across `--context-json event=-` and `--questions -`; the usage text lists the two entries.
- No live test: the wire does not change.

## Related Issues

- wip/cba (`--each`), blocked on this issue.
- wip/ndr (named contexts and `ContextSource`), wip/4c6 (`-` and the once-per-run rule).

## Acceptance Criteria

- [ ] `--context-json` takes the six forms `--context` takes, and the model sees the parsed JSON value in place of a string, alone or as one field of the named object.
- [ ] Every message names `--context-json` when that is the flag typed, and the mix, repeated-name, and `-` once rules run across both flags.
- [ ] A value that is not valid JSON, including empty text, exits 10 before any model call with a message that carries none of Foundation's text.
- [ ] `--help` and the README describe the flag.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.
