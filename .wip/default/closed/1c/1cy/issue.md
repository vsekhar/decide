---
priority: p2
type: feature
created: 2026-09-23T23:36:43-04:00
updated: 2026-09-24T00:26:14-04:00
---

# Per-question output: --name prints name=answer, --stats and --distribution add tab fields, --show-names goes away

## Summary

Plain output gains per-question detail without widening every line. A named question prints `name=answer`, since its name is its id everywhere. `--stats` adds a tab field with the answer's confidence, probability, and a rating's score. `--distribution` adds one tab field per option, level, or side with its probability. `--show-names` goes away before it ships. Question files carry the per-question flags; run-wide flags stay on the command line.

## User Story

A script batches a routing question with several simple ones in one request, as the README urges for latency and cost. It wants the routing question's whole distribution, to route on a runner-up or a margin, and only the answers of the rest. It gets one wider line and otherwise the output it had. It cuts fields by tab and values by space, and finds an option by name with grep. A person at the terminal reads the same line and sees why the model chose what it chose.

## Design Decisions

Decided with the user on 2026-09-23 over a long exchange. The rejected forms are recorded because they were the obvious ones.

- **Per question, not per run.** `--stats` and `--distribution` follow a question like `--min-confidence`, so one question that needs detail does not change the other lines. No run-wide form: "before the first question means every question" was rejected because the README puts run-wide flags at the end of a line, where the same flag would silently mean the last question. Repeat the flag, or use `--json`.
- **`--name` prints the name.** The name is the question's id on the wire, in `--json`, and at the head of its line, so `--show-names` is one idea too many. An unnamed question prints its answer alone: its position label `q<N>` says nothing its line number does not. A line holds `=` only when it is named, because a command-line id cannot hold `=`.
- **The line.** `[name=]answer`; with `--stats`, a tab and `confidence:<n> probability:<n>` plus ` score:<n>` on a rating; with `--distribution`, then a tab per entry `id:<n>`, a level as `id[index]:<n>`, in declared order. Fields by tab, values within the stats field by space, so `cut -fN` and `cut -d' ' -fN` reach everything. Rejected: bare numbers (not self-describing); one flag each for confidence and probability (each is one extra value; the distribution is the thing that can be large, since a model can take 255 options); `=` inside the added fields (two meanings on one line); the stats as several tab fields (the distribution's start column would move with the kind).
- **Distribution entries are tab fields.** Rejected: one field of space-separated entries (an id may hold a space; `--yes "Hell yeah"` is documented); shell quoting of such ids (xargs and eval read it, `cut` cannot); banning spaces in ids (constraining); positions with no ids (unreadable past a few options); banning a separator such as `|` (one more rule). Tab is the one character an id cannot hold, so the only new rule is that an id holds no tab or newline.
- **`=` and `:`.** `=` marks the decision; `:` marks a labeled number. A probability never holds a colon, so a split at the last colon is always right, whatever the id holds.
- **The labels are the tool's words.** `confidence`, the number `--min-confidence` tests; `probability`, the chosen answer's (a no answer prints P(no)); `score`, the expected level index, with levels counted from 0 in declared order and shown in brackets in the distribution. The same words as `--json`.
- **Three decimals** in plain output, fixed width. `--json` keeps the exact value.
- **`--json` implies both flags.** They add nothing under it and are not errors, so a question file that asks for a distribution runs under `--json` unchanged. `--quiet` with either is an error.
- **Question files hold questions and their flags only.** A file describes questions; the command line runs them. Run-wide flags in a file are errors, as wip/qsk already says; its allowed list and wip/hah's schema grow by `--name`, `--stats`, and `--distribution`.
- **Names.** `--stats` and `--distribution`, without `show`: with `--show-names` gone there is no family to match, and the per-question flags are nouns for what a question has.

## Out of Scope

- The question file features themselves (wip/qsk, wip/5r7); they were amended in place.
- Any change to `--json`, including how a yes/no question's probabilities are keyed.
- `--fallback` and streaming, which are unfiled.

## Testing Strategy

The formatter is pure over `Question` and `Outcome` and tested alone. The parser tests are pure over arguments. Run tests use the scripted triage model with the README's numbers, so plain and JSON output are checked against the same answers. No live test: the wire does not change.

## Children

| ID | Title | Blocked on |
|---|---|---|
| wip/hcp | --name prints its question as name=answer; --show-names goes away | - |
| wip/mb3 | --stats and --distribution: per-question tab fields with confidence, probability, score, and id:probability entries | wip/hcp |

Start with wip/hcp; it is small and frees the print loop.

---

_📝 Noted on 2026-09-24 00:26:14-04:00 @ git:f6a434e+local_

Summary (2026-09-24): both children landed. hcp (f6a434e): a named question prints name=answer, --show-names removed. mb3: --stats and --distribution per question, PlainOutput formatter, id whitespace rule. The question-file issues qsk, qc4, and hah were amended at filing. Scope of the title is met; nothing left open here.
