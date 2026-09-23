---
priority: p2
type: task
created: 2026-09-21T20:15:50-04:00
updated: 2026-09-22T22:47:16-04:00
blocked-on:
  - mia
  - rvj
---

# Add --set-config KEY=VALUE, with --project: write one key into a config file and keep the rest

## Objective

`decide --set-config DECIDE_MODEL="typesafe:jev-latest"` writes that key into the home config file, changing only that line, and `--project` writes the working directory's `.decide/config` instead. Every other byte of the file, comments included, stays as it was.

## Context

Part of wip/chc; blocked on wip/mia (the parser is the editor's check) and wip/rvj (the places). Decided with the user on 2026-09-21: the tool writes config as well as reads it. With the TOML subset, a targeted line editor is small and keeps comments, which a re-encode would drop; this is the `git config` model. The flag runs alone, because a bare token is a question in this tool and `decide config set` would be asked of the model. The default target is the home file, as `npm config set` and `gh config set` do; writing a project file by default would create `.decide/` in whatever directory the user happens to be in. The trust rule from wip/rvj holds on write: `DECIDE_MODEL_API_KEY` may not go into a project file.

## Design

- Parser. `--set-config KEY=VALUE` and `--set-config=KEY=VALUE`, split at the first `=` after the flag's own; repeatable; `--project` is a bare flag. `ParseResult` gains `case setConfig(SetConfig)` with `public struct SetConfig: Equatable, Sendable { public var entries: [(key: String, value: String)] as an array of a small Equatable struct; public var project: Bool }`. Rules and messages: any other token on the line (`--context`, a question, a kind flag, `--min-confidence`, `-q`) is `--set-config runs alone`; `--project` without `--set-config` is `--project needs --set-config`; no `=` in the value is `--set-config needs KEY=VALUE`; an unknown key uses the parser's wording, `unknown key "X"; the keys are DECIDE_MODEL and DECIDE_MODEL_API_KEY`; an empty value is `DECIDE_MODEL is empty`; the same key twice on one line is `--set-config sets DECIDE_MODEL twice`; `DECIDE_MODEL_API_KEY` with `--project` is `DECIDE_MODEL_API_KEY is allowed only in the home config, not in a project's`. `--help` still wins anywhere.
- Target. Home: the first home path from `ConfigFiles.paths`, `<xdg>/decide/config`; `HOME` unset or blank is `HOME is not set, so there is no home config`. Project: `<currentDirectory>/.decide/config`.
- Editor, pure, in `ConfigFile`: `public static func setting(_ entries: [(key, value)], in text: String, path: String) throws(ConfigError) -> String`. Parse the existing text first; an invalid file is the usual error, and the user fixes it by hand. For each entry: when the key has a line, replace that line's value with the basic-string encoding of the new value and keep the key's spelling, the spacing around `=`, any trailing comment, and a CRLF ending if the line had one; when it has none, append `KEY = "value"` on its own line at the end, after making sure the text ends with a newline (an empty text gets no leading blank line). Encoding: `"` to `\"`, `\` to `\\`, newline to `\n`, tab to `\t`, carriage return to `\r`; any other control character is `value has a control character`. Then parse the result as a check that it round-trips to the new values.
- Writing, in `Decide.swift` (private): create the parent directories (`~/.config/decide` with mode 0700); read the current text if the file exists (missing means empty; unreadable or not UTF-8 is the loader's error); compute the new text; write it to a temporary file in the same directory; set mode 0600 for the home file; rename over the target. Success prints nothing and returns 0. Any failure prints `Error: <path>: <reason>` and returns 10, and the target is untouched.
- `Decide.usage` gains two lines before `--help`: `--set-config K=V        Write a key to the home config and exit.` and `--project              With --set-config, write ./.decide/config instead.` `README.md`'s Configuration files subsection (from wip/rvj) gains the `--set-config` example and the `--project` sentence.

## Location

- `Sources/DecideCore/CommandLineParser.swift`, `ConfigFile.swift`, `Decide.swift`.
- `README.md` Setup.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `ConfigFileTests.swift`, `DecideRunTests.swift`.

## Tests

- Parser: both flag forms; repeat gives two entries; `--project`; the alone rule against a question, `--context`, and `-q`; `--project` alone; no `=`; unknown key; empty value; the same key twice; the key with `--project`; a value containing `=` keeps everything after the first.
- Editor, pure: replacing keeps every other line byte for byte, comments, spacing, a trailing comment on the edited line, and CRLF; appending to empty text, to text without a trailing newline, and to comment-only text; escaping of each special character; a control character errors; an invalid existing file errors with its line; two entries in one call; the result parses back to the new values.
- Run level, temp `HOME`: writes the home file with mode 0600 and creates the directories; a second write changes only the one line (compare the whole text); `--project` writes `<currentDirectory>/.decide/config`; a file written here reads back through `ConfigFiles.load` with the same value, including a value with a quote and a backslash; the key to a project is refused with exit 10 and no file created; success prints nothing on stdout or stderr and exits 0; an existing malformed file is refused with its line and left as it was.
- By hand, once: `--set-config` in a temp `HOME`, then a real run with the environment cleared picks the model up. One paid request.

## Related Issues

Parent wip/chc. Blocked on wip/mia and wip/rvj. wip/brs set the pattern for a flag that runs alone (`--quiet` is not one, but its grammar checks are the model).

## Acceptance Criteria

- [ ] `decide --set-config DECIDE_MODEL="typesafe:jev-latest"` creates or edits the home file, and a later run with no environment variables uses that model.
- [ ] A second `--set-config` leaves every other byte of the file unchanged, comments included.
- [ ] `--project` writes `./.decide/config`; `DECIDE_MODEL_API_KEY` with `--project` is refused and nothing is written.
- [ ] Bad input exits 10 with a message and leaves the target untouched; success prints nothing and exits 0.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, `swift test --skip DecideLive` passes, and `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-22 22:26:34-04:00 @ git:c568c93+local_

Observed 2026-09-22: README commit c568c93 (the user's rewrite) put a TODO in "Install and Setup": "convert these to `decide --setconfig --model jev-latest --api-key abc123...`". That shape (one flag plus --model and --api-key) differs from this issue's `--set-config KEY=VALUE` with `--project`. Before implementing, confirm with the user which shape they want; the issue's design was decided 2026-09-21 and the TODO is newer.

---

_📝 Noted on 2026-09-22 22:47:16-04:00 @ git:c568c93+local_

From mia's verification 2026-09-22: `ConfigFile.unknownKeyProblem(_:)` interpolates its argument as given; the parser bounds the key to `A-Z a-z 0-9 _ -` before calling it. The `--set-config` parser must do the same check before it names a user-supplied key in a message, or the message can carry arbitrary text from the command line.
