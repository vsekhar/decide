---
priority: p2
type: task
created: 2026-09-22T21:13:36-04:00
updated: 2026-09-22T21:16:22-04:00
may-unblock:
  - 5gr
---

# Bump DecisionModels to 0.3.0, which accepts a request with no state

## Objective

decide builds against DecisionModels 0.3.0: `Package.swift` says `from: "0.3.0"`, `Package.resolved` pins 0.3.0, the build is clean under warnings as errors, and every suite passes, the live one included.

## Context

DecisionModels 0.3.0 makes `DecisionRequest.state` optional and adds `DecisionSession.decide(_ questionnaire: Questionnaire, options:)`, a call with no state for questions that carry their own facts. On the wire, Jev and OpenRouter get an empty string for no state, because both reject a missing or null state (library commit 5171280). Issue 5gr makes `--context` optional in decide and needs that call, so this bump comes first.

Between 0.2.2 and 0.3.0 the library also changed the Apple on-device model's SDK compatibility, let the on-device model and the context merge run with no state, and let its live sum-to-one checks accept the services' two-decimal rounding. Nothing decide uses was renamed. On 2026-09-22 a scratch copy of decide with only the version changed built clean under `-Xswiftc -warnings-as-errors` against 0.3.0, and the 130 offline tests passed with no test changes. The live suite was not run in that check.

## Location

- `Package.swift`: the dependency line.
- `Package.resolved`: the pin. `swift package resolve` rewrites it; commit the result.
- The comment above the dependency line in `Package.swift` says "DEVELOPMENT.md says how to build against a local checkout instead". No such section exists, and none is wanted: decide builds against tagged library releases only, so that each repository stages its updates on its own. Delete the comment.

## Approach

1. In `Package.swift` change `from: "0.2.2"` to `from: "0.3.0"`.
2. Run `swift package resolve`. The DecisionModels entry in `Package.resolved` should then read `0.3.0`. Commit both files.
3. Delete the comment line above the dependency. Do not add a local-checkout section to DEVELOPMENT.md.

4. Build with warnings as errors, run the offline suite, then run the live suite with the key from `.env`, because the provider wire types changed in this release.

No Homebrew change: the formula resolves the package from the tarball at build time, so the pin ships with the next decide release.

## Related Issues

Blocks 5gr (optional `--context`). In the library's tracker (`~/Code/DecisionModels`, `wip show`), jl5 was the stateless-request parent; 8ei and kst set the wire format.

## Acceptance Criteria

- [ ] `Package.swift` says `from: "0.3.0"` and `Package.resolved` pins DecisionModels 0.3.0.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean.
- [ ] `swift test --skip DecideLive` passes with no test changes.
- [ ] `swift test --filter DecideLive` passes with a key.
- [ ] `Package.swift` no longer mentions a local checkout, and DEVELOPMENT.md gains no section about one.

---

_📝 Noted on 2026-09-22 21:16:22-04:00 @ git:a5ba60d+local_

User decision 2026-09-22: drop the Package.swift comment about building against a local checkout; do not add the DEVELOPMENT.md section. decide takes the library through tagged releases only, so that each repository stages its updates independently.
