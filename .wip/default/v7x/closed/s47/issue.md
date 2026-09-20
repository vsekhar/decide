---
priority: p1
type: task
created: 2026-09-20T18:12:48-04:00
updated: 2026-09-20T18:24:45-04:00
may-unblock:
  - 28j
  - wh2
  - mfa
---

# Create the decide Swift package over DecisionModels

## Objective

Create a SwiftPM package in this repo that builds a `decide` executable, a `DecideCore` library that holds all the logic, and a test target. `swift build` and `swift test` pass.

## Context

Part of wip/v7x (the skeleton MVP). The repo holds only README.md, LICENSE.txt, COPYRIGHT.txt, .gitignore, and .env. There is no Swift code. The CLI is a thin layer over the DecisionModels library, a sibling checkout at `../DecisionModels` with no git tags. Every other child of wip/v7x adds code to the targets this issue creates, so this issue must land first.

## Location

New files:

- `Package.swift`
- `Sources/decide/DecideCommand.swift`: the `@main` entry. A stub that calls into `DecideCore` and exits 0. wip/ayd replaces the body.
- `Sources/DecideCore/Decide.swift`: a placeholder `public enum Decide` with a `run` stub so the library target builds. wip/ayd fills it in.
- `Tests/DecideCoreTests/DecideCoreTests.swift`: one placeholder test.
- `.gitignore`: add `.build/` and `.swiftpm/`.

## Approach

Match the library's `Package.swift` (`../DecisionModels/Package.swift`):

- `// swift-tools-version: 6.2`, `swiftLanguageModes: [.v6]`, `platforms: [.macOS(.v15)]`.
- Dependency: `.package(path: "../DecisionModels")`. The library has no tags, so a URL dependency would need a branch. A path keeps both checkouts in step while the CLI is young.
- Targets:
  - `DecideCore` (library): depends on the products `DecisionModels`, `DecisionModelsTypeSafe`, and `DecisionModelsOpenRouter`. wip/mfa needs both providers, so declare them here and keep `Package.swift` out of the later issues.
  - `decide` (executable): depends on `DecideCore` only. One file. Use an `@main` type with `static func main() async` (the file must not be named `main.swift`).
  - `DecideCoreTests` (test target): depends on `DecideCore` and the product `DecisionModelsTesting`. Use Swift Testing (`import Testing`), as the library does (see `../DecisionModels/TESTING.md`).
- Keep all logic in `DecideCore` so tests use `@testable import DecideCore`. SwiftPM tests of executable targets are awkward.
- The library's CI builds with `-Xswiftc -warnings-as-errors`. Keep this package clean under that flag.

The library's macro target pulls in swift-syntax, so the first build takes minutes. That is expected.

## Related Issues

Parent: wip/v7x. Unblocks wip/28j, wip/wh2, wip/mfa.

## Acceptance Criteria

- [ ] `swift build -Xswiftc -warnings-as-errors` succeeds from the repo root.
- [ ] `swift test` runs the placeholder test and passes.
- [ ] `swift run decide` exits 0.
- [ ] `.build/` and `.swiftpm/` are git-ignored.
- [ ] `Package.swift` depends on `../DecisionModels` by path. `DecideCore` links `DecisionModels`, `DecisionModelsTypeSafe`, and `DecisionModelsOpenRouter`. The test target links `DecisionModelsTesting`.

---

_📝 Noted on 2026-09-20 18:24:45-04:00 @ git:24c0c94+local_

Done. Package.swift (tools 6.2, macOS 15, Swift 6 mode) with products: executable decide. Targets: DecideCore (links DecisionModels, DecisionModelsTypeSafe, DecisionModelsOpenRouter), decide (@main DecideCommand, static func main() async, calls Decide.run then exit), DecideCoreTests (Swift Testing, links DecisionModelsTesting). Dependency on ../DecisionModels by path. swift build -Xswiftc -warnings-as-errors clean (also --build-tests); swift test passes 1 placeholder test; swift run decide exits 0. .build/ and .swiftpm/ added to .gitignore. Package.resolved is committed (pins swift-syntax 602.0.0). The first build took about 12 s, not minutes: swift-syntax was already in the shared SwiftPM cache from the library's own builds.
