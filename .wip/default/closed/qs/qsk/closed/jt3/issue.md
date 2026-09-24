---
priority: p2
type: task
created: 2026-09-23T01:04:39-04:00
updated: 2026-09-24T00:51:48-04:00
may-unblock:
  - qc4
---

# Tokenize a text question file: shell-like quoting, # comments, line numbers

# Tokenize a text question file: shell-like quoting, # comments, line numbers

## Objective

A pure function splits the text of a question file into tokens the way a shell splits a command line, and names the file and line of anything it cannot split. It is the foundation of `--questions` (the parent issue); nothing here reads a file or parses a question.

## Context

Part of the parent issue on `--questions`, whose Design Decisions section is the record. Decided with the user on 2026-09-23: shell-like quoting plus `#` comments. The README's example (`triage.txt` under "Question files") quotes each question, indents its flags on their own lines, and separates questions with blank lines; whitespace carries no meaning beyond separating tokens. `ConfigFile.parse` (wip/mia) is the model for a pure, line-aware text function in this codebase: scalars in, a typed error out, no I/O, the path only for messages.

## Location

- `Sources/DecideCore/QuestionFile.swift` (new): `public enum QuestionFile` with `tokens(of:path:)`.
- `Sources/DecideCore/ConfigFile.swift`: `ConfigError`'s doc comment broadens to "A file the tool reads and cannot use: a config file or a question file." Nothing else there changes.
- `Tests/DecideCoreTests/QuestionFileTests.swift` (new).

## Approach

`public static func tokens(of text: String, path: String) throws(ConfigError) -> [Token]` with `public struct Token: Equatable, Sendable { public let text: String; public let line: Int }`, `line` 1-based where the token starts, so the caller can name the line of a token it refuses. Work on Unicode scalars, as `ConfigFile` does.

Grammar:
- Whitespace outside quotes (space, tab, carriage return, line feed) separates tokens and is otherwise dropped. A BOM at the start of the text is dropped.
- A `#` where a token would start (not inside a word or quotes) begins a comment that runs to the end of the line. A `#` inside a word (`a#b`) is an ordinary character.
- `'...'` is literal: every scalar up to the next `'` is kept, backslashes included. No line break rule: a quoted token may span lines.
- `"..."` keeps every scalar up to the next unescaped `"`; `\"` gives `"` and `\\` gives `\`; any other backslash pair is kept as typed (`\n` stays two characters), as a shell keeps it.
- Quotes may open and close inside a word and join with what is around them: `shipping="Delivery issues"` is one token `shipping=Delivery issues`; `"a"'b'c` is `abc`. An empty quoted pair `""` alone is an empty token.
- A backslash outside quotes is an ordinary character. There is no variable or tilde expansion.
- An unterminated quote throws `ConfigError(path: path, line: <the opening quote's line>, problem: "unterminated quote")`.
- No other error exists: any text with balanced quotes tokenizes.

No message holds text from the file, only the path and line.

## Tests

Swift Testing, pure text in. The README's `triage.txt` gives its 14 tokens with the right lines (the second question starts on line 7). Then: leading and trailing whitespace; tabs; CRLF lines; a BOM; a comment line, a trailing comment after a token, a `#` inside a word kept; a `#` right after a closing quote (`"a"#c` is `a` then a comment; a shell agrees because `#` there starts a word); single quotes keeping a backslash and a `#`; double quotes with `\"`, `\\`, and a kept `\n` pair; a quote spanning two lines, the token's line being where it opened; mid-word quotes joining; an empty `""` token; an unterminated double and single quote with the opening line; an empty text and a comment-only text giving no tokens; a bare word with a backslash kept.

Check the grammar against a shell once by hand: `sh -c 'printf "%s\n" "$@"' _ <the fixture's tokens>` is not a check of the tokenizer, but running `xargs -n1 printf '%s\n' < fixture` in `sh` on the accepted fixtures shows the same split for every case without a kept backslash pair, since `xargs` follows the same quoting rules. Note the result on this issue.

## Related Issues

Child of the `--questions` parent. Sibling: the flag and the splice, blocked on this issue. wip/mia set the pattern.

## Acceptance Criteria

- [ ] The README's `triage.txt` tokenizes to its 14 tokens with correct line numbers.
- [ ] Every rule above has a test, and an unterminated quote names the file and the opening line.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean and `swift test --skip DecideLive` passes.

---

_📝 Noted on 2026-09-24 00:45:53-04:00 @ git:a5afa16+local_

Start (2026-09-24): the description is the spec; one addition: TESTING.md's suite list is updated by the coordinator after this and wip/hah land together, so this issue does not touch TESTING.md. Question.detail (wip/mb3) exists now; irrelevant here.

---

_📝 Noted on 2026-09-24 00:49:07-04:00 @ git:a5afa16+local_

Spec corrections (2026-09-24), decided by the coordinator on the worker's report: (1) The README's triage.txt has 15 tokens, not 14: each of the first two questions is 1 + 6 tokens and the third is 1. Its second question starts on line 6, not 7, and the third on line 11. The description's Tests and Acceptance sections are wrong on both counts; the test pins 15 tokens on lines 1, 2-4, 6, 7-9, 11. (2) '"a"#c' is one token a#c, not a then a comment. The grammar (the authoritative section) says # is a comment only where a token would start, and quotes join with the text around them; a shell agrees: sh, bash, and xargs all give a#c. The description's Tests section said the opposite and its stated reason was false. (3) xargs cross-check: same split on every comparable fixture (triage.txt, whitespace, tabs, the # after a quote, single quotes, mid-word quotes, an empty pair, empty text); CRLF, BOM, comments, a quote spanning lines, and a lone '' cannot be compared with BSD xargs, and sh eval agreed with the tokenizer on each of those. (4) Judgement calls kept: Token is nested as QuestionFile.Token with a public init; a line ends only at a line feed, so a lone CR separates tokens but starts no line; in double quotes a backslash before a line feed is a kept pair; a trailing lone backslash inside double quotes is an unterminated quote.

---

_📝 Noted on 2026-09-24 00:51:48-04:00 @ git:a5afa16+local_

Summary (2026-09-24): done. QuestionFile.tokens(of:path:) and QuestionFile.Token in Sources/DecideCore/QuestionFile.swift, pure, on Unicode scalars, with the grammar in its doc comment; ConfigError's doc comment now covers question files; 17 tests in the QuestionFile suite; TESTING.md lists the suite. Verifier: all three criteria hold (as corrected), no blockers, no crash or hang on edge inputs, shell cross-check agrees except where the grammar differs on purpose (a bare backslash outside quotes is ordinary; a backslash before a line feed inside double quotes stays as typed, unlike sh). Acted on its should-fix: a test now pins that nothing is expanded; and its note: a test pins that a lone CR separates tokens but starts no line. Left as observed: a file with CR-only line endings ends a # comment at the next LF, so a comment can eat the rest of such a file; by design since a line ends only at a line feed.
