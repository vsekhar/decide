---
priority: p2
type: task
created: 2026-09-21T20:15:50-04:00
updated: 2026-09-21T20:15:50-04:00
may-unblock:
  - rvj
  - jq1
---

# Parse .decide/config: a TOML subset of key = "value" lines for DECIDE_MODEL and DECIDE_MODEL_API_KEY

## Objective

A pure function turns the text of a config file into the entries it sets, or throws an error that names the file, the line, and the problem. It accepts exactly the subset of TOML the tool needs today and rejects everything else, so any file it accepts is also valid TOML.

## Context

Part of wip/chc, whose Design Decisions section is the record. Decided with the user on 2026-09-21: config files are TOML-shaped, parsed by hand with no dependency, simple key/value pairs only; anything else is an invalid config; every problem is an error the user resolves. The keys, to start, are `DECIDE_MODEL` and `DECIDE_MODEL_API_KEY`. The loader (the second child) reads files and merges entries; the writer (the third child) edits files with this parser as its check.

The invariant that fixes the grammar: every text this parser accepts must be valid TOML 1.0, so a full parser can replace it later without breaking a file. Where the tool refuses valid TOML, the message says "not supported", not "invalid".

## Design

New file `Sources/DecideCore/ConfigFile.swift`:

- `public enum ConfigFile` with `public static func parse(_ text: String, path: String) throws(ConfigError) -> [Entry]`. Pure, no I/O; `path` is only for messages. Entries come back in file order.
- `public struct Entry: Equatable, Sendable { public let key: String; public let value: String; public let line: Int }`, line 1-based, so the loader can name the line of a key it refuses.
- `public struct ConfigError: Error, Equatable, Sendable { public let path: String; public let line: Int; public let problem: String }`. `ExitCode` maps it to `setup` (10); the message is `Error: <path>:<line>: <problem>`, one line through `oneLine`. Line 0 means the whole file (the loader uses it for invalid UTF-8).
- Grammar, line by line. Split on `\n`; drop one trailing `\r`; drop a UTF-8 BOM at the start of the first line.
  - Blank or whitespace-only: skip.
  - First non-space character `#`: a comment, skip.
  - Otherwise `key = value [# comment]`. The key is one or more of `A-Z a-z 0-9 _ -`. Then optional spaces or tabs, `=`, optional spaces or tabs, the value, optional spaces or tabs, and either the end of the line or `#` and a comment. Anything else after the value is `text after the value`.
  - Value: a basic string `"..."` with the escapes `\"`, `\\`, `\n`, `\t`, `\r`; or a literal string `'...'` with no escapes. A `#` inside quotes is part of the value. Other escapes: `unsupported escape \x` (name the character). Unterminated: `unterminated string`. Not a string: a bare word, number, or boolean gets `value must be a quoted string, for example DECIDE_MODEL = "typesafe:jev-latest"`; `"""` or `'''` gets `multi-line strings are not supported`; `[` gets `arrays are not supported`; `{` gets `inline tables are not supported`.
  - A line whose first non-space character is `[`: `tables are not supported`. A key containing `.`: `dotted keys are not supported`. A key starting with `"` or `'`: `quoted keys are not supported`. A line with no `=`: `expected key = "value"`.
  - Key checks: only the two known keys; another bare key is `unknown key "X"; the keys are DECIDE_MODEL and DECIDE_MODEL_API_KEY`. A key set twice in one file: `DECIDE_MODEL is set twice, first on line N`. An empty string value: `DECIDE_MODEL is empty`. Values are not trimmed; `ModelConfiguration` trims later.
- No message ever contains a value from the file. Messages name keys and constructs only, so a key's value cannot land in a log.

## Location

- `Sources/DecideCore/ConfigFile.swift` (new): `ConfigFile`, `Entry`, `ConfigError`.
- `Sources/DecideCore/ExitCode.swift`: the `ConfigError` arms in `code(for:)` and `message(for:)`.
- `Tests/DecideCoreTests/ConfigFileTests.swift` (new); `ExitCodeTests.swift` gains table rows.

## Tests

Swift Testing, pure text in, no files.

- Accepts: both keys with basic strings; literal strings; each escape decoded; a comment line, a trailing comment, a `#` inside quotes kept; blank lines; CRLF; a BOM; spaces or tabs around `=` present or absent; entries in file order with the right line numbers.
- Rejects, each with the exact message and line: bare value; integer; boolean; unknown key; quoted key; dotted key; repeated key (names the first line); empty value; unterminated string; unsupported escape; `[table]`; `key = [1]`; `key = { a = 1 }`; `"""`; no `=`; text after the value.
- Every accepted fixture is valid TOML. Paste them into a TOML validator once by hand and note the check on this issue; the tests cannot run one without a dependency.
- ExitCode: a `ConfigError` maps to 10; its message is `Error: path:3: problem`, one line, and the table and `messageShape` tests cover it.

## Related Issues

Parent wip/chc. wip/fjj put usage and setup errors at 10.

## Acceptance Criteria

- [ ] `ConfigFile.parse` accepts the subset above and rejects everything else with a message that names the file, line, and construct.
- [ ] No error message can contain a value from the file.
- [ ] `ConfigError` exits 10 through `ExitCode` with a one-line message.
- [ ] Every accepted test fixture is valid TOML, checked once by hand.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean and `swift test --skip DecideLive` passes.
