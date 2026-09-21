---
priority: p2
type: task
created: 2026-09-20T21:27:42-04:00
updated: 2026-09-20T21:27:42-04:00
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
