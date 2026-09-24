---
priority: p2
type: feature
created: 2026-09-24T02:48:54-04:00
updated: 2026-09-24T04:00:06-04:00
---

# Per-question unsure handling: every line prints, and --fallback

## Summary

Today one question below its `--min-confidence` bar takes the whole run down: nothing prints, exit 2. The bar is already per question on the input side; this feature makes the outcome per question too. An unsure question prints an empty answer while the others print theirs, and a new question flag, `--fallback <value>`, names what an unsure question prints instead, which makes it a decision. `--fallback` also covers a remote error, when every question has one. Stderr reports each unsure question with the prefix `Unsure:`.

## User Story

A script runs a batch of triage questions over a ticket. The team question is sure, the refund question is not. Today the script gets nothing and must rerun or drop the bar. After this feature it gets `team=returns` and `refund=`, exit 2, and can route the ticket while a person decides the refund. With `--fallback No` on the refund question it gets `refund=No`, exit 0, and the safe branch runs without a special case.

## Design Decisions

Taken with the user on 2026-09-24:

1. **Every line prints.** An unsure question with no fallback prints an empty answer, `name=` or a blank line; the run exits 2; stderr names each unsure question, its confidence, and its bar. The empty answer cannot collide with a real one, because an empty option, level, or side value is refused. Exit 0 still means every line is a decision; non-empty stdout no longer implies exit 0, and the README says to check the code first.
2. **`--fallback` is per question**, like `--min-confidence`, on the line and in a JSON question file. The safe answer differs by question, so a run-wide value would not serve. It fires when the question is below its bar, or when the run has a remote error.
3. **A yes/no question's fallback is its yes or no value.** The exit code of a one-yes/no-question run then always follows a side. The README's `-q --fallback false` becomes `--fallback no`, and its sentence about "the fallback exit code" goes. Any other kind takes any non-empty single-line value; it need not be an option or level id.
4. **Remote errors are all-or-nothing.** When every question has a fallback, the run prints every fallback, keeps the error line on stderr, and exits as decided. When any question has none, nothing prints and the code is 11, as today: the tool cannot assert it is unsure of anything, so an empty answer would say something false. Setup errors (10) never take a fallback.
5. **Exit code precedence.** 11 for a remote error not fully covered; else 2 when any unsure question has no fallback; else the decided code, where one yes/no question uses the printed answer, fallback included.
6. **stderr.** The unsure line keeps its clauses and changes its prefix from `Error: unsure:` to `Unsure:`, since exit 2 is a decision-like state. It prints whenever any question is below its bar, fallback or not, so a reader knows the model was unsure even when the run exits 0.
7. **JSON.** An unsure line keeps its key: `"answer": null` and `"unsure": true` with the model's numbers. A fallback line has `"answer": "<fallback>"`, `"unsure": true` when the model was below the bar, and `"fallback": true`; on the remote path it has no `score`, `confidence`, or `probabilities`. Sure lines are byte-for-byte as before.
8. **Plain stats fields** stay the model's numbers on an unsure or fallback line; a remote fallback line has none.

## Out of Scope

- Streaming and `--each`; the README's per-event rule stays a promise.
- A run-wide fallback or an "unsure mode" flag.
- Retrying a failed request, or any library change.

## Testing Strategy

Scripted models in `DecideRunTests` prove each path: a batch with one unsure question, with and without a fallback; one yes/no question with a fallback of each side, with and without `-q`; a thrown `DecisionError.timeout` with every question covered and with one uncovered; `--json` on each. Unit tests cover the parser's new flag and the side rule, the JSON file's `fallback` key, the two printers, and `Unsure.report`. No live test: the wire does not change.

## Child Issues

- wip/a0g: an unsure question prints an empty answer; the other lines print, exit 2, stderr says `Unsure:`. Start here.
- wip/oin: `--fallback` on a question and in a JSON file, and the remote-error path. Blocked on wip/a0g.

---

_📝 Noted on 2026-09-24 04:00:06-04:00 @ git:a506026_

Summary (2026-09-24): done through wip/a0g (a2d24c9) and wip/oin (a506026). All eight design decisions are in: every line prints with an empty answer for an unsure question, --fallback per question on the line and in JSON files, the yes/no side rule, all-or-nothing remote errors, the exit-code precedence, the Unsure: prefix, the JSON shapes, and the model's numbers on unsure and fallback lines. Both children were verified against their criteria with scripted and live runs; 503 offline tests and 5 live tests pass.
