---
priority: p2
type: task
created: 2026-09-22T23:00:58-04:00
updated: 2026-09-22T23:00:58-04:00
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
