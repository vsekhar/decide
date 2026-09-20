---
priority: p2
type: feature
created: 2026-09-20T18:13:27-04:00
updated: 2026-09-20T18:13:27-04:00
---

# decide skeleton: classification questions over one context

## Summary

Build the first working `decide` binary, as the README describes it, with the smallest useful surface: one context (a literal string or `@file`), one or more classification questions with `--option` lists, one request for all of them, and one answer id per line on stdout. The model and key come from `DECIDE_MODEL` and `DECIDE_MODEL_API_KEY`. The code is Swift, a thin layer over the DecisionModels library at `../DecisionModels`.

## User Story

A shell user runs the README's Classification and Batch questions examples and gets the answers on stdout, with exit codes a script can branch on.

## Design Decisions

- **Model naming.** `DECIDE_MODEL=provider:model`, split at the first colon. The provider part matches the library's `DecisionModelIdentity.provider` (`typesafe` or `openrouter`). The model part goes to the provider verbatim, so versions travel in each provider's own form: `typesafe:jev-latest`, `typesafe:jev-1.13.0`, `openrouter:typesafe/jev-1.13`. A name with no colon is an error. Decided with the user on 2026-09-20 over the alternatives (slash separator, bare default to typesafe, two variables). Both providers ship in the skeleton, since the scheme exists to tell them apart.
- **Key.** `DECIDE_MODEL_API_KEY` is passed to the provider when set. When unset, the provider reads its own variable (`TYPESAFE_API_KEY` or `OPENROUTER_API_KEY`) and reports itself unavailable if that is missing too.
- **Argument parsing is hand-written.** The grammar interleaves positional questions with per-question flags (`"Q1" --option a "Q2" --option b`). swift-argument-parser collects every `--option` into one array, so it cannot express this. No dependency beyond the library.
- **Wire-level questionnaire.** The runner builds `QuestionSpec` values and reads `Answers.records`, not `Choose<Option>`. The library has no `ChoiceOption` conformance for `String`, and the CLI only needs string ids back. Question ids are `q1`...`qN` in order.
- **Option descriptions.** `--option id=description` is accepted, because the README says options carry descriptions. A bare option uses its id as the criterion summary.
- **Flag forms.** Both `--flag value` and `--flag=value`, as the README uses both.
- **Exit codes** follow the README appendix: 0 decided, 2 setup or input error, 3 runtime error. Stdout is empty on error.
- **Package layout.** `DecideCore` library holds all logic; the `decide` executable is one file; a `DecideCoreTests` target uses Swift Testing. Dependency on `../DecisionModels` by path, since the library has no tags.
- **Tests** use `ScriptedModel` from `DecisionModelsTesting`, so no network in the unit suite. One live suite named `DecideLive` fails without a key and is skipped by name, as the library's TESTING.md does.

## Out of Scope

- `--questions @file` (the `.decide` line format) and JSON questionnaires
- `--json` output
- `--level`, `--yes`, `--no`, `--min-confidence`, `--exit`, `--fallback`
- Named or composite contexts, `--context-json`, `-` for stdin, `--each` streaming
- `--model` and `--model-api-key` command-line overrides
- The on-device model and the composition wrappers
- A `--` terminator for a question that starts with `-`

## Testing Strategy

Each child carries its own unit tests with `ScriptedModel`. The entry point issue adds run-level tests through `Decide.run` with injected streams and one live test against Jev. Done means the README's classification example and the batch example (limited to `--option` questions) work from a shell with a real key.

## Children

| ID | Title | Blocked on |
|---|---|---|
| wip/s47 | Create the decide Swift package over DecisionModels | - |
| wip/28j | Parse the command line into a context source and choice questions | s47 |
| wip/wh2 | Build the questionnaire and run all questions in one request | s47 |
| wip/mfa | Pick the model from DECIDE_MODEL and map errors to exit codes | s47 |
| wip/ayd | Wire the entry point: load context, decide, print answers | 28j, wh2, mfa |

Start with wip/s47. Then wip/28j, wip/wh2, and wip/mfa can run in parallel. wip/ayd integrates them. wip/28j and wip/wh2 both touch `Sources/DecideCore/Invocation.swift`; whichever lands first creates it.
