---
priority: p2
type: task
created: 2026-09-20T21:27:42-04:00
updated: 2026-09-20T21:59:38-04:00
---

# Add GitHub Actions CI: macOS and Linux tests, live suite on push, coverage

## Objective

Every push to `github.com/vsekhar/decide`, every pull request from a fork, and every manual run builds the package with warnings as errors and runs the tests on macOS and on Linux. On a push, the macOS job also runs the `DecideLive` suite against Jev with a repository secret and uploads line coverage to Codecov. The README shows a CI badge and a coverage badge, and TESTING.md says what CI runs and how to reproduce it.

## Context

The repo has no `.github` folder. The library this tool wraps has the house pattern at `../DecisionModels/.github/workflows/ci.yml`, described in its `TESTING.md` under "Continuous integration". Mirror that file with the differences below; the header comment and step comments are prose, so write them fresh in the house style (short sentences, active voice) rather than copying.

What differs from the library:

- **No iOS job.** `Package.swift` lists macOS 15 only; a CLI has no iOS target.
- **One live suite, `DecideLive`.** It sends one request per run. It reads `DECIDE_MODEL` and a key from the environment and fails, never skips, without them (`Tests/DecideCoreTests/DecideLiveTests.swift`; the suite accepts the provider's own variable, so `TYPESAFE_API_KEY` is enough). Set `DECIDE_MODEL: typesafe:jev-latest` as a plain `env` value on the test step, not a secret, and pass `TYPESAFE_API_KEY` from `secrets.TYPESAFE_API_KEY`. A fork's pull request has no secrets, so it runs with `--skip DecideLive`.
- **The dependency comes from GitHub by tag** (`Package.swift` pins DecisionModels from 0.1.0; `Package.resolved` is committed), so CI needs no sibling checkout. swift-syntax still builds from source through the library's macro target, which is why the build cache matters; key it on `hashFiles('Package.resolved')` as the library does.
- **Coverage names this package's test bundle:** `$bin/decidePackageTests.xctest/Contents/MacOS/decidePackageTests`. Naming `$PWD/Sources` keeps the report to `DecideCore` and `decide`.
- **Linux is a first.** Nothing has built this package on Linux yet. The Foundation calls it makes all exist in swift-corelibs-foundation: `String(contentsOfFile:encoding:)` (`Sources/DecideCore/Decide.swift`), `CharacterSet.newlines` (`ExitCode.swift`), `FileHandle.standardOutput.write(_:)` and `standardError` (`StandardStreams.swift`), `ProcessInfo.processInfo.environment` and `exit` (`Sources/decide/DecideCommand.swift`). One known gap: on Linux, reading a file that is not valid UTF-8 may not throw the way Darwin does. No test covers that path today (`DecideRunTests` covers only a missing file), so the Linux job will not catch a difference there; note it in TESTING.md rather than adding a test here. If the Linux job fails on a corelibs difference that a small guard fixes, fix it; anything larger, stop and report.

Costs to know: each push spends one Jev request per job that runs the live suite, so two if Linux runs it too. Keep the Linux job's live run, as the library does, since it is the one check of `URLSession` from `FoundationNetworking` against the service for this package.

## Design

`.github/workflows/ci.yml`:

- Triggers: `push`, `pull_request`, `workflow_dispatch`. `permissions: contents: read`. A `concurrency` group on `github.ref` with `cancel-in-progress`. The same `if:` as the library on every job, so a pull request from a branch in this repository does not run twice.
- Job `macos` ("macOS tests"): `runs-on: macos-26`, `timeout-minutes: 30`, `sudo xcode-select -s /Applications/Xcode_26.6.app` from an `XCODE_APP` env, `actions/checkout@v7`, `actions/cache@v6` on `.build` with a key that names the OS, arch, Xcode version, "coverage", and the `Package.resolved` hash. One test step: `swift test -Xswiftc -warnings-as-errors --enable-code-coverage` plus `--skip DecideLive` when `github.event_name == 'pull_request'`, with `DECIDE_MODEL` and `TYPESAFE_API_KEY` in its env. One run, because each coverage run clears the one before it. Then, not on pull requests: export `coverage.lcov` with `xcrun llvm-cov export -format=lcov` from `$bin/codecov/default.profdata` and the test bundle path above, over `$PWD/Sources`; upload with `codecov/codecov-action@v7`, `token: secrets.CODECOV_TOKEN`, `files: coverage.lcov`, `disable_search: true`, `fail_ci_if_error: true`.
- Job `linux` ("Linux tests"): `runs-on: ubuntu-latest`, `container: swift:6.3.3-noble` (the Swift that Xcode 26.6 ships, patch and OS pinned), `timeout-minutes: 30`, checkout, cache on `.build` keyed with "swift6.3.3" and the resolved hash, one test step with `shell: bash` (a container job's default shell has no arrays): `swift test -Xswiftc -warnings-as-errors` plus the same skip rule and env. No coverage; the macOS job owns the report.
- Header comment: why pushes run everything and pull requests only from forks; why the live suite runs on push; that the Linux job is the one check of the Linux claim; a pointer to TESTING.md.

`README.md`: after the `# decide` title line, add the two badge lines the library's README has, with `decide` in place of `DecisionModels`:

```
[![CI](https://github.com/vsekhar/decide/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/vsekhar/decide/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vsekhar/decide/branch/main/graph/badge.svg)](https://codecov.io/gh/vsekhar/decide)
```

`TESTING.md`: a "Continuous integration" section after "The whole suite", modeled on the library's: a two-row table of jobs (runner, what runs); that the tests run in one `swift test` because coverage clears between runs; the command that reproduces the macOS step (`set -a; . ./.env; set +a; swift test -Xswiftc -warnings-as-errors --enable-code-coverage`); the coverage export command with this package's bundle name; the two secrets and how to set them from the repo root (`gh secret set TYPESAFE_API_KEY` prompts for the value; do not use `gh secret set -f .env`, since `.env` holds more than that key; `gh secret set CODECOV_TOKEN` after adding the repo at codecov.io); that a fork's pull request skips the live suite and the upload; the Linux note on invalid UTF-8 above; and the Docker command to run the offline suite in the same image locally, from the library's TESTING.md with `--skip DecideLive`.

Manual steps for the repository owner, listed in the issue because an agent cannot do them without the values: enable the repo on codecov.io and set `CODECOV_TOKEN`; set `TYPESAFE_API_KEY`. An agent with the key in its environment can run `gh secret set TYPESAFE_API_KEY --body "$TYPESAFE_API_KEY"` after sourcing `.env`, without printing it.

## Location

- `.github/workflows/ci.yml` (new)
- `README.md` (two badge lines under the title)
- `TESTING.md` (new section)

## Out of Scope

- Running the `Examples/` scripts in CI; the live suite already runs the same path.
- A release or install workflow; there is no release process yet.
- A test for the invalid-UTF-8 file path on Linux; note the gap in TESTING.md and file a follow-up if the behaviors differ.

## Related Issues

wip/v7x holds the skeleton this checks; wip/ayd the live suite's design. No blockers. wip/fjj (exit-code renumbering) and wip/eh3 can land before or after this; none of them changes the commands CI runs.

## Acceptance Criteria

- [ ] A push to `main` runs the macOS and Linux jobs and both pass, with the live suite included and coverage uploaded (needs the two secrets set first).
- [ ] `swift test -Xswiftc -warnings-as-errors --enable-code-coverage` passes locally with `.env` sourced, and the export command produces a `coverage.lcov` that names only files under `Sources`.
- [ ] The README shows both badges and the CI badge reads passing after the first green run on `main`.
- [ ] TESTING.md's new section lets a new contributor reproduce the macOS step and the Linux run without reading the workflow.
- [ ] A pull request from a fork would run without secrets: the workflow's skip rule is keyed on `github.event_name`, as the library's is (a real fork cannot be tested from this repo; check the expression).

---

_📝 Noted on 2026-09-20 21:39:42-04:00 @ git:a0cb374+local_

Design record. Implemented directly in the main context, no worker: the yml body mirrors ../DecisionModels/.github/workflows/ci.yml and the rest is prose, so a brief would have held the whole change. Decisions: (1) DECIDE_MODEL sits in each Tests step's env, not top-level, per the issue; TYPESAFE_API_KEY comes from the secret and no DECIDE_MODEL_API_KEY is set, which works because ModelConfiguration.makeModel passes a nil key and Jev then reads TYPESAFE_API_KEY itself. (2) Both jobs run the live suite on push, so a push costs two Jev requests. (3) The skip rule is SKIP_LIVE=${{ github.event_name == 'pull_request' }} plus a bash array, as the library does; an empty array expands cleanly under /bin/bash 3.2 without set -u, checked locally. (4) The macOS job's default shell is bash; the container job names bash because sh has no arrays. (5) TESTING.md gets one 'Continuous integration' section with the Docker commands at its end, not a separate Linux section, per the issue; the Docker live command passes DECIDE_MODEL and DECIDE_MODEL_API_KEY, matching the .env the file documents. Facts found: all three secrets (TYPESAFE_API_KEY, OPENROUTER_API_KEY, CODECOV_TOKEN) were already set on vsekhar/decide before this work, so the owner's manual steps are done. Docker is not installed on this Mac, so nothing has run the Linux job locally; the first push is the first Linux build. The 0.1.0 tag is annotated; its commit e115b352 matches Package.resolved and the library's CI is green on it, macOS and Linux. Local reproduction of the macOS step uses the CI-shaped env: .env sourced, then env -u DECIDE_MODEL_API_KEY -u OPENROUTER_API_KEY DECIDE_MODEL=typesafe:jev-latest swift test -Xswiftc -warnings-as-errors --enable-code-coverage. Dead code: the change adds no symbols, only a workflow and prose.

---

_📝 Noted on 2026-09-20 21:40:20-04:00 @ git:a0cb374+local_

Local check of the macOS step, CI-shaped env (no DECIDE_MODEL_API_KEY, no OPENROUTER_API_KEY, DECIDE_MODEL=typesafe:jev-latest, TYPESAFE_API_KEY from .env): swift test -Xswiftc -warnings-as-errors --enable-code-coverage passed, 56 tests in 6 suites, DecideLive included, zero warnings, none of the library's 'LLVM Profile Error' lines locally. The export command wrote a coverage.lcov whose SF: lines name only the eight files under Sources/DecideCore; Sources/decide/DecideCommand.swift is absent because the tests do not link the executable, so TESTING.md says the report covers DecideCore. Lines 97.35 percent, StandardStreams.swift 0 percent (the run tests inject String streams). Removed the local coverage.lcov; neither repo ignores it.

---

_📝 Noted on 2026-09-20 21:50:00-04:00 @ git:a0cb374+local_

Verifier report: all five acceptance criteria hold for everything checkable without a push. One should-fix and four notes, all fixed: (1) TESTING.md's 'gh secret set --body "$TYPESAFE_API_KEY"' sentence contradicted the documented .env shape, which has DECIDE_MODEL_API_KEY and no TYPESAFE_API_KEY, so a contributor could store an empty secret; dropped the sentence, kept the prompting form. (2) ci.yml comments were largely the library's words where the issue asked for fresh prose; rewrote every comment, and a diff with comments stripped shows the body unchanged. (3) The Linux UTF-8 note claimed the read may not throw on Linux; swift-foundation shares one implementation that throws on both, so TESTING.md now says the error's code and message may differ and that no test covers a corrupt file on either platform. (4) Linked the library's TESTING.md by URL, since a contributor has no local copy. (5) Added coverage.lcov to .gitignore, since the documented export writes it to the package root. Verifier also confirmed: the if: expressions match the library's byte for byte; the library's identical runner and container labels ran green on tag 0.1.0 today; Jev reads TYPESAFE_API_KEY itself when the tool passes a nil key; two Foundation calls not in the issue's list, trimmingCharacters(in:) and Data(string.utf8), exist in corelibs; Synchronization is cross-platform; no Darwin-only import. Still unverified, needs a push: the two jobs passing on GitHub, the Linux build itself, the Codecov upload, and the badges turning green. Summary: added .github/workflows/ci.yml, two README badges, a Continuous integration section in TESTING.md, and a .gitignore line.

---

_📝 Noted on 2026-09-20 21:59:38-04:00 @ git:a8af8bd_

Pushed a8af8bd to main on the user's instruction; run 35552477780 passed. macOS tests: 1 min 33 s, 56 tests in 6 suites, DecideLive passed, zero warnings, coverage.lcov (8032 bytes) uploaded to Codecov with the action reporting success. Linux tests: 2 min 22 s, 56 tests in 6 suites, DecideLive passed, so URLSession from FoundationNetworking reached Jev; the first Linux build of this package needed no guard. Both jobs ran without a skip flag, as a push should. The macOS log shows 12 of the library's 'Internal Error: DecodingError' / 'LLVM Profile Error' pairs, so TESTING.md's hedged note about them is right for this package too. SwiftPM downloaded a prebuilt swift-syntax MacroSupport zip on macOS, which is why that job is fast even cold; Linux fetched swift-syntax from source. The CI badge reads passing on main via the workflow runs API. The codecov badge was not fetched from this session (the curl was declined); the upload was accepted and queued at https://app.codecov.io/github/vsekhar/decide/commit/a8af8bd. Acceptance criteria 1 and 3 now hold.
