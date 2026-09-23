---
priority: p2
type: task
created: 2026-09-22T16:17:58-04:00
updated: 2026-09-22T20:32:34-04:00
---

# Add --version and show the version in --help; the version is a constant bumped at release

## Objective

`decide --version` prints the version string and exits 0. The `--help` text shows the same version string and lists `--version`. `--version` with any other argument still prints the version, and is also a usage error.

## Context

The tool has no version anywhere: not in the binary, not in the help text. Homebrew installs tagged releases (0.1.1 today), so users need a way to see which one they have, and the Homebrew formula's test block wants a version to assert on. SwiftPM injects no version into an executable, and Homebrew builds from a tarball with no `.git`, so the version has to be a constant in the source that the release procedure bumps.

## Location

- `Sources/DecideCore/Version.swift` (new): the constant, `Decide.version`, a bare version like `"0.1.2"`.
- `Sources/DecideCore/CommandLineParser.swift`: `ParseResult` gains a version case; `parse` detects `--version`.
- `Sources/DecideCore/Decide.swift`: `usage` shows the version and lists the flag; `run` handles the new case.
- `Tests/DecideCoreTests/CommandLineParserTests.swift` and `DecideRunTests.swift`: new tests next to the `--help` ones (`helpAnywhere`, `help`).
- `DEVELOPMENT.md`, Release section: bump the constant before tagging.
- `TESTING.md`, "What the suite cannot see": the stdout rule still holds; note the check for `--version`.
- Follow-up in the tap repo, not this one: the formula test in `vsekhar/homebrew-tap` adds `assert_match version.to_s, shell_output("#{bin}/decide --version")` on the next bump pull request. test-bot then fails a bump whose constant lags the tag.

## Approach

**Parser.** Check for `--version` before the `--help` check, because `--version --help` must take the version path (see below). Add to `ParseResult`:

```swift
case version(alone: Bool)
```

`parse(["--version"])` returns `.version(alone: true)`. Any argument list that contains `--version` and anything else returns `.version(alone: false)`, whatever the other arguments are, even `--help` or invalid flags; the parser does not look at them. `--version=x` is not `--version`; it falls through to `unknown flag: --version=x` as today. No `-V` short form.

**Entry point.** In `Decide.run`:

- `.version(alone: true)`: print `Decide.version` to stdout, return `ExitCode.decided`.
- `.version(alone: false)`: print `Decide.version` to stderr, then `Error: --version takes no other arguments` to stderr, return `ExitCode.setup` (10). Stdout stays empty. Do not print the usage text here; `report(_:to:)` is for usage errors that need it.

Design decision on the error case: the request says the version prints and the run is an error. TESTING.md's rule is that stdout is empty on every exit of 2 or more, so that a script reading answers never gets something else. Both hold when the version goes to stderr in the error case. In a terminal the user sees the version either way. If the version must reach stdout in the error case too, change the run test and the TESTING.md note, and say so in the issue.

**Help text.** `usage` becomes an interpolated string. Put `decide \(version)` as the first line, then a blank line, then the existing `Usage:` block. Add one entry to the flag list, next to `--help`:

```
  --version              Print the version and exit. Takes no other argument.
```

**Version constant.** `public static let version = "0.1.2"` on `Decide`, or whatever the next tag will be; the person who releases sets it. Add step 0 to the Release section of DEVELOPMENT.md: set `Decide.version` to the tag, commit, then tag. Explain that the Homebrew formula test is the guard against forgetting.

## Related Issues

None open. wip/brs set the exit code conventions this follows.

## Acceptance Criteria

- [ ] `CommandLineParser.parse(["--version"]) == .version(alone: true)`.
- [ ] `parse(["--version", "--help"])`, `parse(["--help", "--version"])`, and `parse(["--context", "c", "Q", "--version"])` all give `.version(alone: false)`.
- [ ] `parse(["--version=1"])` throws `unknown flag: --version=1`.
- [ ] `Decide.run(arguments: ["--version"], ...)` writes `Decide.version + "\n"` to stdout, nothing to stderr, exit 0.
- [ ] `Decide.run(arguments: ["--version", "--context", "c"], ...)` writes nothing to stdout, the version line then the error line to stderr, exit 10. The model is never called.
- [ ] `Decide.usage` contains `Decide.version` and the text `--version`. The existing `help` and `helpAnywhere` tests still pass.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean and `swift test --skip DecideLive` passes.
- [ ] DEVELOPMENT.md's Release section says to bump `Decide.version` before tagging. TESTING.md's stdout rule mentions `--version`.
- [ ] The binary check from TESTING.md holds: `decide --version --context x; echo $?` prints the version on stderr, nothing on stdout, and 10.

---

_📝 Noted on 2026-09-22 16:36:52-04:00 @ git:e847d23+local_

The tap-side follow-up is issue qwm in ~/Code/homebrew-tap: add assert_match version.to_s on decide --version to the formula's test block, in the same bump pull request as the first release that has --version.

---

_📝 Noted on 2026-09-22 20:22:21-04:00 @ git:e847d23+local_

---

_📝 Noted on 2026-09-22 20:22:33-04:00 @ git:e847d23+local_

Design record (fills the gaps the issue left open; the issue's Approach section stands as written).

- Version value: "0.1.2". Tags are 0.1.0 and 0.1.1; the branch is bump-decide-0.1.1.
- Version.swift is `extension Decide { public static let version = "0.1.2" }` with a doc comment. `usage` stays a `static let` on Decide and interpolates `\(version)` unqualified; both are lazy statics, so order does not matter.
- Parser: after the empty guard and before the help check, `if arguments.contains("--version") { return .version(alone: arguments.count == 1) }`. No `-V`. `--version=x` falls through to the unknown-flag error with no new code.
- Entry point: the error case prints two literal lines to stderr, `version` then `Error: --version takes no other arguments`, and returns ExitCode.setup. It does not build a UsageError and does not call `report`, because there is no usage text to print.
- Help text: first line `decide \(version)`, blank line, then the existing block unchanged. The `--version` entry goes right after `--help, -h`, with its description at the same column (25).
- README needs no change: it lists no flags and never mentions --help.
- DEVELOPMENT.md: the Layout list gains Version.swift after Decide.swift. The Release section gets a new step 1 (set the constant, commit) and steps 1-4 become 2-5; a numbered list that starts at 0 reads oddly, so the issue's "step 0" is step 1 here. The step says the tap's formula test on `decide --version` is what catches a constant that lags the tag (tap issue qwm adds that assertion in the same bump PR as the first --version release).
- TESTING.md "What the suite cannot see": a paragraph and a two-line shell check after the first code block, showing that `--version` with another argument keeps stdout empty and exits 10.
- Tests: parser gets `version`, `versionAnywhere` (mirrors helpAnywhere, includes `--bogus --version`), `versionWithValue`. Run tests get `version`, `versionWithArguments` (asserts the exact stderr text and `model.callCount == 0`), and `usageShowsVersion` (hasPrefix "decide <version>\n" and contains "--version").

---

_📝 Noted on 2026-09-22 20:27:17-04:00 @ git:e847d23+local_

Corrections to the design record: the tree is on main at e847d23, not a bump-decide-0.1.1 branch (that name came from a stale status). Worker judgement calls, accepted: the Release intro paragraph was rewrapped at the file's ~76-column width after the new words; one parser test line runs to 108 columns, which the file already does in nine other places; the usage doc comment stays "The text --help prints."

---

_📝 Noted on 2026-09-22 20:32:34-04:00 @ git:e847d23+local_

Done. Version.swift holds Decide.version = "0.1.2". The parser returns .version(alone:) before the help check; Decide.run prints the version to stdout and exits 0 alone, or to stderr with 'Error: --version takes no other arguments' and exit 10 with any other argument, and never builds a model. --help opens with 'decide 0.1.2' and lists --version. Six new tests; build clean under warnings-as-errors; 130 offline tests pass; the binary checks in TESTING.md hold. Verifier found no defects; three cosmetic notes applied (TESTING.md comment names both stderr lines; parser doc comment says --help wins only when --version is absent; help text says 'arguments' to match the error). One verifier note left as designed: a context text of exactly --version now takes the version path, like --help does. Next release: follow DEVELOPMENT.md Release step 1, and land tap issue qwm in the same bump PR.
