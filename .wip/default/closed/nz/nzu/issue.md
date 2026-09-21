---
priority: p2
type: feature
created: 2026-09-20T20:33:48-04:00
updated: 2026-09-20T22:58:40-04:00
---

# Leveling and yes/no questions in the skeleton

## Summary

Add the README's two other decision types to the skeleton: `--level` questions (a rating, answered with the chosen level id) and yes/no questions (a verdict, answered with the yes or no value). A question with no `--option` or `--level` is a yes/no question, the simplest kind; `--yes` and `--no` set its two values. Everything else stays as wip/v7x left it: one context, inline questions, one request per run, one answer per line. Batches mix the three kinds freely because each question carries its own kind. The confidence bar, `--min-confidence`, is a separate feature (wip/xhd) that applies to every kind.

## User Story

A shell user runs the README's Leveling, Yes or no, and Batch questions examples on one context (without the `--min-confidence` flags for now) and gets one answer per line, with the same exit codes as today.

## Design Decisions

- **Kind by flags.** `--option` makes a choice, `--level` makes a rating, and a question with neither is a verdict. `--yes` and `--no` decorate a verdict. A verdict flag beside `--option` or `--level`, or `--option` beside `--level`, is a usage error that names the question. `Question.options` becomes `Question.kind`, an enum with the three cases; a level reuses the `Option` struct because it has the same two fields. The one cost: a question whose `--option` flags were forgotten no longer fails, it prints `yes` or `no`.
- **Rating answer.** The printed level is the most likely one, with a tie going to the lower level, as the library's `Rating.value` does. Levels go on the wire as criteria in order; the CLI maps the record's indices back to ids.
- **Verdict answer.** The yes value prints when P(yes) is at least 0.5, as the library's `Verdict.value` does. Defaults are `yes` and `no`.
- **Descriptions.** `--level id=text`, `--yes value=text`, `--no value=text` follow the `--option id=text` rule. A bare level sends its id as the criterion, as a bare option does. A bare yes or no value sends no criterion, because "Hell yeah" is a label, not a description of the case.
- **Confidence is the library's number.** `Outcome.confidence` is the DESIGN.md section 6.1 value for every kind: the provider's reported confidence when it gives one, else the per-kind formula. Nothing in this feature gates on it. wip/xhd adds `--min-confidence` as a modifier on every kind with an "unsure" exit code.
- **Outcome shape stays.** `Outcome.answer` is the printed string; `probabilities` are keyed by level id or by the yes and no values, ready for a later `--json`.

## Out of Scope

- `--min-confidence` (wip/xhd), `--exit`, and `--fallback`
- `--json` output, `--questions @file`, JSON questionnaires
- Named or composite contexts, so the README's refund example that reads `refund_policy.txt` is not runnable yet; the refund question runs on the ticket alone
- Any change to the README text; it already describes both kinds

## Testing Strategy

Each child adds parser, runner, and run-level tests with `ScriptedModel`. The one live test grows to the README's three-question batch, which is still one request. `Examples/ticket.sh` becomes the README batch example minus its `--min-confidence` flag, run by hand with a real key.

## Children

| ID | Title | Blocked on |
|---|---|---|
| eh3 | Add --level questions | - |
| h9x | Add --yes and --no; a bare question is a verdict | eh3 |

Start with wip/eh3; it carries the `Question.Kind` change the other builds on. wip/xhd follows both.

---

_📝 Noted on 2026-09-20 22:58:40-04:00 @ git:4edb41b+local_

Both children shipped: wip/eh3 (8c90147) and wip/h9x (the commit after it). The parent's scope holds: the README's Leveling, Yes or no, and Batch questions examples run on one context without --min-confidence and print one answer per line, checked by hand against the real model; three kinds mix in one batch and one request; Question.kind is the three-case enum; a level reuses Option; a bare yes or no value sends no criterion; confidence is the library's number, computed over the whole scale (a decision added under eh3); exit codes are unchanged by this feature (fjj renumbered them separately). Out of scope stays out: --min-confidence is wip/xhd, in progress now; --exit, --fallback, --json, named contexts, and README changes were not touched. Closing.
