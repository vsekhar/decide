---
priority: p2
type: feature
created: 2026-09-23T01:04:39-04:00
updated: 2026-09-24T01:05:26-04:00
---

# Text question files and --questions

# Text question files and --questions

## Summary

`decide` takes questions from a plain text file: `decide --context @ticket.txt --questions @triage.txt`. The file mimics the command line without the program name: a question, then zero or more flags that belong to it, then the next question; whitespace is only a separator, quotes group text, and `#` starts a comment. The file's tokens take the flag's place in the argument list and parse as if typed, so the tool gains no second grammar. The README's "Question files" section (edited by the user 2026-09-23) is the spec.

## User Story

A team keeps its triage questions in `triage.txt` under version control and runs the same questions against every ticket with one short command, editing the file rather than a script. A reviewer reads the file and sees the command line they already know.

## Design Decisions

Decided with the user on 2026-09-23.

- **Shell-like tokens, plus `#` comments.** Whitespace splits tokens across lines; double quotes take `\"` and `\\`; single quotes are literal; quotes may sit inside a word; no expansion of any kind; `#` at a token's start comments to the end of the line. An unquoted multi-word question becomes several questions, as on a command line; the README quotes every question.
- **Spliced in place, repeatable, mixing freely.** The file's questions sit where the flag was among command-line questions, so output order follows the line. Question numbers in messages count across the whole run and match output order.
- **A file holds questions and their flags only.** `--option`, `--level`, `--yes`, `--no`, `--min-confidence`, `--name`, `--stats`, and `--distribution` (the last two from wip/mb3). Any other flag in a file is an error naming the file and line, so a file cannot change the context, the model, quietness, or read another file.
- **The parser stays pure.** Expansion is a separate step with an injected reader; `Decide.run` supplies the real one. Help, version, and `--set-config` are decided before any file is read, as the context file is today.
- **File problems reuse `ConfigError`** (path, line, problem), whose meaning broadens to any file the tool reads; the message shape `Error: <path>:<line>: <problem>` and exit 10 are already built.
- **`--questions <text>` without `@` is the text itself**, as `--context` works, so a script can pass a generated file's content.
- **JSON question files are a later feature.** A file starting with `{` is refused with "not supported yet", so the README's `triage.json` example fails clearly until then.

## Out of Scope

- JSON question files, named questions, `--json` output (the README's second example).
- `--questions -` for stdin.
- Any change to the question grammar itself.

## Testing Strategy

The tokenizer is pure and tested on text, with the README's file as the first fixture. The expansion is tested with an in-memory reader, never the disk. Run-level tests use temp files and the scripted triage model, and prove the README example end to end. No live test: the wire format does not change, so a scripted model proves everything (TESTING.md).

## Children

| ID | Title | Blocked on |
|---|---|---|
| jt3 | Tokenize a text question file: shell-like quoting, # comments, line numbers | - |
| qc4 | --questions @file: splice a question file's tokens into the command line | jt3 |

Start with the tokenizer.

---

_📝 Noted on 2026-09-23 23:37:06-04:00 @ git:8fc9672+local_

Amended 2026-09-23 while filing wip/1cy (per-question output): the allowed-flag list in Design Decisions gains --name, --stats, and --distribution. Run-wide flags stay errors in a file: a file describes questions, the command line runs them.

---

_📝 Noted on 2026-09-24 01:05:26-04:00 @ git:cb3a694+local_

Summary (2026-09-24): both children landed: wip/jt3 (9a4a3f8, the tokenizer) and wip/qc4 (this commit, the flag and the splice). The README's triage.txt runs against a scripted model and prints its three answers in order; --questions splices in place, repeats, and mixes with line questions; run-wide flags in a file are errors; help, version, and --set-config win over a bad file. The scope of the title is met.
