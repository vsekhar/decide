---
priority: p2
type: task
created: 2026-09-22T23:00:58-04:00
updated: 2026-09-22T23:37:29-04:00
---

# Edit a config file's text: set keys and keep every other byte

# Edit a config file's text: set keys and keep every other byte

## Objective

A pure function takes the text of a `.decide/config` file and a list of key/value pairs, and returns the text with those keys set. A key that has a line keeps that line's spelling, spacing, trailing comment, and line ending, and only its value changes. A key that has none is appended as `KEY = "value"`. Every other byte of the text stays as it was, comments included. The result parses back to the new values.

## Context

Part of wip/jq1 (`--set-config`), under wip/chc. The parent's flag shape is still open (see the notes on jq1), but every shape ends in key/value pairs to write, so the editor is independent of it. This is the `git config` model: a targeted line edit, not a re-encode that would drop comments. The parser (wip/mia) is the editor's check: an invalid existing file is the usual `ConfigError`, and the user fixes it by hand.

## Location

- `Sources/DecideCore/ConfigFile.swift`: the editor, next to the parser, since it reuses the parser's line splitting and string scanning.
- `Tests/DecideCoreTests/ConfigFileTests.swift`: the editor's tests.

## Approach

- `public static func setting(_ pairs: [(key: String, value: String)], in text: String, path: String) throws(ConfigError) -> String` on `ConfigFile`.
- First `parse(text, path:)`. An invalid file throws as usual. The entries give each key's line number.
- Split the text into lines that keep their own ending: `\r\n`, `\n`, or none (the last line without a newline). Do not reuse `lines(of:)`, which drops endings; add a private splitter, or refactor `lines(of:)` to record the ending and have both callers share it. A BOM on the first line stays where it is.
- For each pair, in order: if the key has an entry, rebuild that line. The value's span on the line comes from the parser's own scanner: refactor `parseValue` to also return the value's start (the opening quote) and end (after the closing quote) positions, so the editor replaces `line[start..<end]` with the encoded value and keeps everything before and after, including the trailing comment and the line ending. A key with no entry appends `KEY = "value"` as a new line at the end. Before the first append, when the text is non-empty and does not end with a line break, add one. Appended lines end with `\n`, or `\r\n` when the text's last line ending is `\r\n`. An empty text gets no leading blank line. Setting the same key twice in one call edits the line the first pair wrote, so the last value wins.
- Encoding, always a basic string: `"` to `\"`, `\` to `\\`, newline to `\n`, tab to `\t`, carriage return to `\r`. Any other control character (`isControl`, minus the three the escapes cover) throws `ConfigError(path: path, line: 0, problem: "value has a control character")`. An empty value throws `ConfigError(path: path, line: 0, problem: "<KEY> is empty")`, the parser's wording. An unknown key throws with `unknownKeyProblem`; the caller bounds the key to the bare-key set first (the tool's `--set-config` parser will), and the editor checks `keys.contains` before naming the key in a message.
- Last, `parse` the result; if it throws, propagate. It should not, and the tests prove it.

## Related Issues

Parent wip/jq1. The parser is wip/mia (closed). The loader is wip/rvj.

## Acceptance Criteria

- [ ] Replacing a value keeps every other byte: other lines, comments, the key's spelling, the spacing around `=`, a trailing comment on the edited line, and a CRLF ending on it.
- [ ] Appending works on empty text, on text without a trailing newline, and on comment-only text, and adds no leading blank line to empty text.
- [ ] Each of the five special characters is escaped; another control character is refused; an empty value and an unknown key are refused with the parser's wording; an invalid existing file is refused with its line.
- [ ] Two pairs in one call both land; the result parses back to the new values, including a value with a quote and a backslash.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean and `swift test --skip DecideLive` passes.

---

_📝 Noted on 2026-09-22 23:12:36-04:00 @ git:5f4fa3a+local_

Design addendum 2026-09-22:
- Check order per pair: the key first (below), then an empty or whitespace-only value → "<KEY> is empty" at line 0, then encoding (a control character the escapes do not cover → "value has a control character" at line 0), then the edit.
- Unknown key: when every scalar of the key is a bare-key scalar (`isKeyScalar`), throw `unknownKeyProblem(key)`; otherwise throw `problem: "the key is not a bare key"` without naming it, so no message carries arbitrary caller text. Line 0 in both.
- Splitting: refactor `lines(of:)` into a private `splitLines(of:) -> [(body: [Unicode.Scalar], ending: String)]` where `ending` is "\r\n", "\n", or "" for the last line without a break; `lines(of:)` becomes `splitLines(of:).map(\.body)` with the same BOM handling on the first body, so the parser is unchanged. The editor rebuilds the text as `body + ending` per line, so an unchanged line is byte-identical. The BOM is dropped from the first body by `lines(of:)` only; `splitLines` keeps it, and the editor works on `splitLines`, so a BOM survives an edit.
- Value span: `parseValue` returns `(value: String, start: Int, end: Int)`, `start` the opening quote's index and `end` the index after the closing quote; `parseLine` ignores the positions. The editor finds the line for a key from `parse`'s entries, calls `parseValue` again on that line (it cannot throw, the line already parsed), and splices `body[..<start] + encoded + body[end...]`.
- Encoding lives in a private `basicString(encoding value: String) -> String` that returns the quoted, escaped form.
- Tests go in `ConfigFileTests.swift` under the existing suite, each named for what it keeps or refuses; a private `edit(_:pairs:)` helper calls `ConfigFile.setting(pairs, in: text, path: path)`.

---

_📝 Noted on 2026-09-22 23:24:44-04:00 @ git:5f4fa3a+local_

Implemented 2026-09-22 by a worker from the issue plus the addendum; diff read in the main context and matches. Worker's choices, accepted: an empty key gets "the key is not a bare key" (the parser's own bare-key test, not a bare `allSatisfy`); a literal-string line becomes a basic string on edit, pinned by a test; the appended line's ending is the text's last non-empty ending, computed once; `replace` keeps one unreachable `shapeProblem` throw that typed throws needs. Checks: build with warnings as errors clean; offline suite 214/214 (18 new); the 34 existing ConfigFile tests pass unchanged, so the parser refactors moved nothing; 17 result strings the tests assert on parse with tomllib to the expected keys (the BOM one with the BOM stripped, as before). Dead-code check by hand: every private helper has a caller; `parseValue`'s new positions are read by `replace`; nothing removed; no import. Sent to the verifier.

---

_📝 Noted on 2026-09-22 23:37:29-04:00 @ git:5f4fa3a+local_

Verified 2026-09-22: all five acceptance criteria hold. Parser parity against HEAD over 17,844 texts with zero divergences; byte preservation over 17,880 replacements and 2,668 appends; 11,621 results parse with tomllib to the same values; four mutants die. The final re-parse of the result is defence in depth that no test observes (the earlier note overstated that); it stays as the only guard should the encoder and the parser ever drift. Notes on the record: a value that is only U+0085, U+2028, or U+00A0 counts as empty, the same predicate the parser uses; a BOM-only text gets a blank-looking line before an appended entry, valid TOML; HEAD had 33 ConfigFile tests, not 34.
