---
priority: p2
type: feature
created: 2026-09-24T15:01:19-04:00
updated: 2026-09-27T14:22:48-04:00
may-unblock:
  - cba
  - 90o
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

---

_📝 Noted on 2026-09-27 14:14:45-04:00 @ git:7e72281+local_

Design record (2026-09-27), read with the issue's Approach. Decisions taken past the Approach, and the prose that lands in code and docs.

## Decisions

1. `Context.single` takes a default: `case single(ContextSource, ContextFormat = .text)`. A probe confirmed the case compiles and `.single(.file("x")) == .single(.file("x"), .text)`. Every existing `--context` expectation in the parser tests stays as written, and only the two pattern matches in Sources (`Context.readsStandardInput`, `Decide.loadState`) gain the second binding. New tests for `--context-json` spell the format out: `.single(.text("[1]"), .json)`.
2. The shared value grammar stays shared, as the Approach says. Consequence, logged for a follow-up and not fixed here: an unnamed inline JSON value with no whitespace before its first `=` is a name attempt, so `--context-json '{"a":"x=y"}'` is refused as `--context-json name "{"a":"x" is not valid: ...`, exactly as `--context 'http://x=y'` is today (the parser test `invalidContextName` documents that rule). Spaces in the JSON, `@file`, or `-` avoid it.
3. Foundation's decoder, probed on this Mac: top-level `"just text"`, `45`, `true`, `null`, `[1, 2, 3]`, and objects all decode into `State`; empty text and whitespace-only text both fail; a leading BOM is dropped before the decode so both platforms behave the same; `1e999` fails (State's own dataCorrupted), and that is fine: it is "not valid JSON" for our purposes.
4. The parse lives in one private helper in Decide.swift, `state(of:as:named:stderr:)`, so `.single` and `.named` share it and wip/cba can call the same path per event.
5. Messages: `Error: context "<name>" is not valid JSON` (named) and `Error: the context is not valid JSON` (unnamed). No Foundation text: the detail differs on Linux.

## Prose for code

`ContextFormat` doc comment:
```
/// How the run turns a context's text into the state the model sees.
public enum ContextFormat: Sendable, Equatable {
    /// The text itself, as one string. What `--context` gives.
    case text
    /// The text parsed as JSON, so the model sees its structure: an object,
    /// an array, a number, a boolean, null, or a string. What
    /// `--context-json` gives. Text that is not valid JSON stops the run.
    case json
}
```

`Context` doc comment:
```
/// The context a run is about: one value, or an object of named values.
/// Each value is its source's text, or that text parsed as JSON, as its
/// format says.
```

`Context.single` doc comment:
```
    /// One unnamed `--context` or `--context-json`. The model sees its
    /// text as the state, or the parsed JSON value with `.json`.
    case single(ContextSource, ContextFormat = .text)
```

`Context.named` doc comment:
```
    /// Every `--context <name>=...` and `--context-json <name>=...`, in
    /// command-line order. The model sees one JSON object keyed by name, so
    /// a question can refer to a name in prose. A `.json` context's field
    /// holds its parsed value beside the text of the others. One named
    /// context is a one-field object. The parser keeps names unique; the
    /// run keeps the last of a repeat.
```

`NamedContext` doc comment (struct): `/// One \`--context <name>=...\` or \`--context-json <name>=...\`: the name, where its text comes from, and how the run reads that text.` Add the field:
```
    /// Whether the model sees the text itself or its parsed JSON value.
    public let format: ContextFormat
```
and `init(name: String, source: ContextSource, format: ContextFormat = .text)`.

`ContextSource` doc comments: each case's comment gains `--context-json`, e.g. `.text`: "The text itself, from `--context "..."`, `--context <name>=...`, or the `--context-json` forms of those."; `.file`: "A path, from `--context @path`, `--context <name>=@path`, or the `--context-json` forms. The run reads it as UTF-8."; `.standardInput`: "The whole of standard input, from `--context -`, `--context <name>=-`, or the `--context-json` forms. The run reads it as UTF-8, once."

`CommandLineParser.parse` doc comment, one sentence after "...which a line may name once.": "`--context-json` is `--context` whose value is parsed as JSON, in every form, and the two flags share one list, so the rules above run across both."

`ContextEntry` becomes `case unnamed(ContextSource, ContextFormat)` and `case named(NamedContext)`.

`contextEntry(from:flag:format:)` doc comment: "Reads one `--context` or `--context-json` value; `flag` is the one typed, for the messages, and `format` is how the run reads the text. The text before the first `=` is a name attempt when it is non-empty and holds no whitespace: a valid name makes a named context, and an invalid one is an error. Any other value is unnamed: the text itself, or a file when it starts with `@`." Messages use `flag`: `"\(flag) name \"\(name)\" is not valid: a letter or _ then letters, digits, or _"`, `"\(flag) \(name)= has no value"`, and the prefixes `"\(flag) "` and `"\(flag) \(name)="` passed to `contextSource`, whose doc comment's last sentence becomes: "`prefix` is what the names-no-file message quotes before the `@`: the flag and a space for an unnamed value, the flag and `ticket=` for a named one."

`Decide.run` doc comment, after "`-` as a `--context` value or a `--questions` value reads standard input, once per run.": "A `--context-json` value, whatever its form, is parsed as JSON before the model sees it."

`loadState` doc comment: "Reads the run's context into the state the model sees. One context is its text, or its parsed value with `.json`. Named contexts are one object, each field the text or parsed value of the context of that name, read in command-line order. Prints the reason to `stderr` and returns nil when a file or standard input does not read, or when a `.json` context's text is not valid JSON."

The helper in Decide.swift:
```
    /// The state one context's text gives: the text itself for `.text`, or
    /// its parsed value for `.json`. A leading BOM is dropped before the
    /// parse, as a question file's is. Prints the reason to `stderr` and
    /// returns nil when the text is not valid JSON; empty text is not. The
    /// message carries none of Foundation's detail, which differs by
    /// platform. `name` is the context's name, or nil for an unnamed one.
    private static func state(
        of text: String,
        as format: ContextFormat,
        named name: String?,
        stderr: inout some TextOutputStream
    ) -> State? {
        switch format {
        case .text:
            return .text(text)
        case .json:
            var scalars = text.unicodeScalars[...]
            if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
            let data = Data(String(scalars).utf8)
            guard let state = try? JSONDecoder().decode(State.self, from: data) else {
                let which = name.map { "context \"\($0)\"" } ?? "the context"
                print("Error: \(which) is not valid JSON", to: &stderr)
                return nil
            }
            return state
        }
    }
```

Usage text, after the `--context <name>=-` line, same columns as the lines around it:
```
  --context-json <json>          Context parsed as JSON, so the model sees its structure:
                                 objects, arrays, numbers, and booleans, not one string.
                                 Takes @<path> and - like --context.
  --context-json <name>=<json>   A named JSON context, in the same three forms.
```

README, under Usage, right after the "Compose context from multiple sources" example block's `no` line, a blank line, then:
```
# Give the model structured context; --context-json parses its value as JSON
$ decide --context-json order='{"total": 45.00, "days_since_delivery": 12}' \
         --context refund_policy=@refund_policy.txt \
         "Should we issue a refund?"
yes
```

---

_📝 Noted on 2026-09-27 14:15:50-04:00 @ git:7e72281+local_

Filed wip/90o (P3) for the grammar consequence in design decision 2: compact unnamed inline JSON holding = with no earlier whitespace is refused as a bad name. Not fixed here; blocked on this issue so the parser change lands first.

---

_📝 Noted on 2026-09-27 14:22:48-04:00 @ git:7e72281+local_

Summary (2026-09-27). Built as the design record says, by a worker; verified by the verifier with no blockers.

What landed: `ContextFormat` (`.text`, `.json`), `NamedContext.format`, `Context.single(_:_ = .text)`; `--context-json` in the parser through the shared `contextEntry(from:flag:format:)`, every message built from the flag typed; the parse in `Decide.state(of:as:named:stderr:)`, shared by `.single` and `.named` so wip/cba can call it per event; the two usage entries; the README example; 15 new test functions and cases in three existing tests. Build with warnings as errors clean; 540 offline tests pass; the live suite passes with the key; the binary prints nothing on stdout on the new exit-10 path.

Verifier notes, for the record:
- The line-wide messages (`every --context needs a name ...`, `--context names "a" twice`) still say `--context` when only `--context-json` is on the line. That is the design (unchanged rules); AC2 reads loosely there.
- On Darwin, Foundation's JSONDecoder skips a leading UTF-8 BOM by itself, so `contextJSONFileWithBOM` passes there even without the explicit drop; the drop is for Linux, where the decoder may not. A double-BOM test would guard it on Darwin but likely go red on Linux, so none was added.
- Whitespace-only text was added to the not-JSON run test after verification.
