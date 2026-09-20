---
priority: p2
type: task
created: 2026-09-20T18:12:57-04:00
updated: 2026-09-20T18:35:20-04:00
blocked-on:
  - s47
may-unblock:
  - ayd
---

# Pick the model from DECIDE_MODEL and map errors to exit codes

## Objective

Read `DECIDE_MODEL` and `DECIDE_MODEL_API_KEY` from an environment dictionary, build the matching `DecisionModel`, and map every error the CLI can meet to an exit code and a one-line stderr message.

## Context

Part of wip/v7x. Decided with the user: `DECIDE_MODEL` is `provider:model`, split at the first colon. The provider part matches `DecisionModelIdentity.provider` in the library. The model part goes to the provider verbatim, so versions travel in each provider's own form:

```sh
DECIDE_MODEL=typesafe:jev-latest
DECIDE_MODEL=typesafe:jev-1.13.0
DECIDE_MODEL=openrouter:typesafe/jev-1.13
DECIDE_MODEL=jev-latest              # error: no provider
```

Providers:

- `typesafe` builds `Jev(version:apiKey:)` from `DecisionModelsTypeSafe` (`../DecisionModels/Sources/DecisionModelsTypeSafe/Jev.swift:43`). Its identity provider is `typesafe`.
- `openrouter` builds `OpenRouterAlpha(model:apiKey:)` from `DecisionModelsOpenRouter` (`../DecisionModels/Sources/DecisionModelsOpenRouter/OpenRouterAlpha.swift:49`). Its identity provider is `openrouter`.
- Any other provider is a configuration error whose message lists the two providers.

The key: pass `DECIDE_MODEL_API_KEY` as `apiKey:` when it is set and not blank. When it is unset, pass `nil`. Each provider then reads its own variable (`TYPESAFE_API_KEY` or `OPENROUTER_API_KEY`). If that is also missing, the provider's availability is `.unavailable(.notConfigured(...))` and the session throws `DecisionError.unavailable` before any network call.

The README's exit code table: 0 decided, 2 setup or input error (bad usage, model or key missing), 3 runtime error (network, timeout, rate limit). Command-line overrides `--model` and `--model-api-key` are out of scope for the skeleton.

`DecisionError` (`../DecisionModels/Sources/DecisionModels/DecisionError.swift`) has no `LocalizedError` or `CustomStringConvertible` conformance, so the CLI owns the messages. The enum is not frozen; switch with `@unknown default`.

## Approach

- `Sources/DecideCore/ModelConfiguration.swift`:
  - `struct ModelConfiguration { let provider: String; let model: String; let apiKey: String? }`.
  - `init(environment: [String: String]) throws(ConfigurationError)`. Missing or blank `DECIDE_MODEL` throws `.missingModel`. No colon, or an empty part on either side, throws `.malformedModel(String)`. An unknown provider throws `.unknownProvider(String)`. Blank `DECIDE_MODEL_API_KEY` counts as unset.
  - `func makeModel() -> any DecisionModel`: switch on the provider.
- `Sources/DecideCore/ExitCode.swift`:
  - `enum ExitCode { static let decided: Int32 = 0; static let usage: Int32 = 2; static let runtime: Int32 = 3 }`.
  - `func exitCode(for error: any Error) -> Int32` and `func message(for error: any Error) -> String`.
  - `ConfigurationError` is 2.
  - `DecisionError` cases that are setup or input errors are 2: `.unavailable(.notConfigured)`, `.unauthorized`, `.invalidQuestion`, `.unsupported`, `.contextSizeExceeded`.
  - `DecisionError` cases that are runtime errors are 3: `.unavailable` with any other reason, `.rateLimited`, `.overloaded`, `.timeout`, `.refused`, `.guardrailViolation`, `.insufficientProbabilityQuality`, `.malformedResponse`, `.transport`, and `@unknown default`.
  - `CancellationError` and any other error are 3.
  - Messages are one line and start with `Error: `. For `.transport` use the README's own wording, `cannot reach decision model server`. For a missing model, name the variable and show the scheme with the two examples. Never print the key.
- wip/ayd adds the `UsageError` from wip/28j to the mapping as 2.

## Tests

`Tests/DecideCoreTests/ModelConfigurationTests.swift` and `Tests/DecideCoreTests/ExitCodeTests.swift`, Swift Testing:

- `typesafe:jev-latest` builds a model whose identity is `DecisionModelIdentity(provider: "typesafe", name: "jev-latest")`.
- `openrouter:typesafe/jev-1.13` builds a model whose identity is `("openrouter", "typesafe/jev-1.13")`. The slash stays in the model part.
- `jev-latest` and `typesafe:` throw `.malformedModel`. `foo:bar` throws `.unknownProvider`. Unset throws `.missingModel`.
- A blank `DECIDE_MODEL_API_KEY` gives `apiKey == nil`.
- Do not test provider availability here. The public `Jev` and `OpenRouterAlpha` initializers read the process environment for their fallback key, so such a test would depend on the developer's shell. The library covers availability.
- A table-driven test maps every `DecisionError` case to its expected exit code.

## Related Issues

Parent: wip/v7x. Blocked on wip/s47. wip/ayd calls `ModelConfiguration` and the exit code mapping.

## Acceptance Criteria

- [ ] The four `DECIDE_MODEL` examples above behave as listed.
- [ ] `DECIDE_MODEL_API_KEY` reaches the provider. Blank means unset.
- [ ] Each `DecisionError` case maps to 2 or 3 as listed. Unknown errors map to 3.
- [ ] Messages are one line and never include the key.
- [ ] Tests pass under `swift test`.

---

_📝 Noted on 2026-09-20 18:26:04-04:00 @ git:ccab071+local_

Design record (2026-09-20). Decisions beyond the issue text: (1) The mapping functions are static members of 'enum ExitCode': ExitCode.code(for:) and ExitCode.message(for:), beside the three constants. (2) 'enum ConfigurationError: Error, Equatable { case missingModel; case malformedModel(String); case unknownProvider(String) }'. (3) ModelConfiguration is Equatable. (4) DECIDE_MODEL is trimmed of surrounding whitespace before the checks; blank after trimming counts as missing. The provider part must match 'typesafe' or 'openrouter' exactly (lowercase). The model part is not trimmed further and goes to the provider verbatim. (5) If '@unknown default' on the DecisionError switch warns under -warnings-as-errors, the switch is written exhaustively instead and the report says so. (6) UsageError (wip/28j) is not in this mapping; wip/ayd adds it, because the two issues land in separate worktrees. (7) Message texts are fixed in the worker brief; the key never appears in any message. Implemented by a worker in a scratch worktree, then copied back.

---

_📝 Noted on 2026-09-20 18:30:25-04:00 @ git:e31b7ea_

Refinement (2026-09-20, in the worker brief): 'provider' is 'public enum Provider: String, CaseIterable, Sendable { case typesafe, openrouter }' nested in ModelConfiguration, not a String. makeModel() then switches exhaustively with no dead default branch. ConfigurationError.unknownProvider still carries the raw string the user typed. The message list (exact texts) is in the brief and will be checked by the verifier against ExitCode.swift.

---

_📝 Noted on 2026-09-20 18:35:19-04:00 @ git:e31b7ea+local_

Landed from the worker's worktree: ModelConfiguration.swift (ConfigurationError, ModelConfiguration with nested Provider enum), ExitCode.swift, ModelConfigurationTests.swift (12 tests), ExitCodeTests.swift (5 tests). '@unknown default' raised no warning under -warnings-as-errors, so it stays on the three switches over DecisionError and DecisionError.Unsupported; the switch over DecisionModelAvailability.Reason is plain exhaustive. Worker judgement calls, accepted: Foundation import for trimming; oneLine() walks unicode scalars so a CRLF (one Character) still turns into spaces; the test table is a function, not a global let, to satisfy Swift 6 sendability. Main-tree build clean; full offline suite 46 tests in 5 suites passes. Dead code kept on purpose: ExitCode.decided has no caller until wip/ayd.
