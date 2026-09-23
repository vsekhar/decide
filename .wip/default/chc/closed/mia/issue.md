---
priority: p2
type: task
created: 2026-09-21T20:15:50-04:00
updated: 2026-09-22T22:50:30-04:00
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

---

_📝 Noted on 2026-09-22 22:24:26-04:00 @ git:c568c93+local_

Design record 2026-09-22, filling what the Design section leaves open:

- Message for line 0: `Error: <path>: <problem>` with no line number, because line 0 means the whole file (`ConfigError` keeps `line == 0`; only the message drops it). Every other line is `Error: <path>:<line>: <problem>`. Both go through `oneLine`.
- The known keys come from `ModelConfiguration.modelVariable` and `.apiKeyVariable`, exposed as `public static let keys: [String]` on `ConfigFile` so the writer (jq1) uses the same list and wording. The unknown-key problem text is built once by a module-internal `static func unknownKeyProblem(_ key: String) -> String`.
- Per-line check order, so a line is judged on its own shape before file-level rules: leading spaces or tabs stripped; empty → skip; `#` → skip; `[` → "tables are not supported"; `"` or `'` → "quoted keys are not supported"; no `=` → `expected key = "value"`; key part trimmed of spaces/tabs; key containing `.` → "dotted keys are not supported"; key empty or with a character outside `A-Z a-z 0-9 _ -` → `expected key = "value"`; key not in `keys` → the unknown-key problem; then the value; then "<KEY> is set twice, first on line N"; then "<KEY> is empty".
- Value: after `=`, spaces or tabs skipped. First character `"""` or `'''` → "multi-line strings are not supported" (check the triple before the single quote); `"` → basic string; `'` → literal string; `[` → "arrays are not supported"; `{` → "inline tables are not supported"; anything else, including nothing at all → `value must be a quoted string, for example DECIDE_MODEL = "typesafe:jev-latest"`. After the closing quote: spaces or tabs, then end of line or `#` (a comment needs no space before it, as in TOML); anything else → "text after the value".
- Basic-string escapes: `\"` `\\` `\n` `\t` `\r` only. Any other `\x` → `unsupported escape \x` naming the one character after the backslash; a backslash at the end of the line is "unterminated string". Literal strings have no escapes.
- Control characters: a raw character U+0000–U+0008, U+000A–U+001F, or U+007F inside either string kind → "control character in the value". Tab (U+0009) is allowed. TOML forbids these, and the Objective's invariant (every accepted file is valid TOML) needs the check; a lone CR mid-line lands here too, since only one trailing CR per line is dropped.
- Whitespace means space and tab only, as in TOML. A BOM (U+FEFF) is dropped from the start of the first line only.
- ExitCode: `case is ConfigError: setup` in `code(for:)`, `case let error as ConfigError: oneLine(message(for: error))` in `message(for:)`, with a private `message(for: ConfigError)`. Tests: two table rows (line 3 and line 0), and a `configMessage` test pinning both message shapes.
- TOML validity of the accepted fixtures: checked with Python's `tomllib` after implementation (available locally), each fixture parsed and its keys compared to the entries the parser returns. The result goes in a note.

---

_📝 Noted on 2026-09-22 22:35:16-04:00 @ git:c568c93+local_

Implemented 2026-09-22 by a worker from the Design plus the design-record note; diff read in the main context. Worker's choices, accepted: the parser works on Unicode scalars, not Characters, because CRLF is one Character and combining marks would join; `ConfigFile` sits first in the file so the invariant is its doc comment; `unknownKeyProblem` joins the keys with " and ". One fix in the main context: a control character right after a backslash now reports "control character in the value" instead of an unsupported escape, so no message carries a raw control character (a test for it was added and shown to fail before the guard). TOML validity: the worker ran Python tomllib over all 20 accepted fixtures; every one parses and its keys and values match the parser's entries. One caveat: tomllib refuses a text that starts with a BOM, while this parser drops it, as utf-8-sig decoders do; a BOM belongs to the encoding, not the document, so the invariant stands for the decoded text. Checks: build with warnings as errors clean; offline suite 166/166 in 6 suites (31 new in ConfigFile, 2 rows and 1 test new in ExitCode). Dead-code check by hand: every added symbol has a caller (`keys` and `unknownKeyProblem` are used by the parser and a test; the writer will use them too); nothing removed; no unused parameter or import (ConfigFile.swift imports nothing). Sent to the verifier.

---

_📝 Noted on 2026-09-22 22:46:58-04:00 @ git:c568c93+local_

Verifier findings 2026-09-22 and the fixes, all in the main context. The design record's control-character rule was scoped to strings; TOML forbids the same characters in comments, and a bare CR is a line ending only when an LF follows. Both let the parser accept text TOML refuses (the verifier's 70,000-text differential fuzz against tomllib found no other class). Fixes: (1) a comment, whole-line or trailing, with a control character throws "control character in a comment"; (2) `lines(of:)` strips a CR only before an LF, so `DECIDE_MODEL = "a"\r` at the end of a file is "text after the value" and `# c\r` is a control character in a comment. Two tests were added and shown to fail before the fixes; the offline suite is 168/168. Corrected rule for the record: a control character (U+0000–U+0008, U+000A–U+001F, U+007F) anywhere in a line except inside nothing at all, that is in a string or a comment, is an error; tab is allowed in both. Also added `ConfigFile.swift` to DEVELOPMENT.md's Layout list (and `UnsureError.swift`, which the list had missed). Left as is: a tab after a backslash names the tab in "unsupported escape", cosmetic; `unknownKeyProblem` relies on its caller to bound the key, which jq1 must keep in mind (noted on jq1).

---

_📝 Noted on 2026-09-22 22:50:30-04:00 @ git:c568c93+local_

Verified 2026-09-22 after the fixes: all five acceptance criteria hold. Verifier's differential fuzz against tomllib, 190,000 texts in four passes, found zero TOML-invalid accepts beyond the leading BOM and zero value divergences; 40,000 valid-subset texts had zero wrong rejections; six mutants each fail their named test. Offline suite 168/168. Notes left as is: a tab after a backslash is named raw in the unsupported-escape message (tab is not a control character); a BOM after line 1 reports the shape message with no hint it is invisible.
