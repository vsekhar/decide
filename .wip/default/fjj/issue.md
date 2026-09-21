---
priority: p2
type: task
created: 2026-09-20T21:20:36-04:00
updated: 2026-09-20T21:20:36-04:00
may-unblock:
  - xhd
---

# Renumber exit codes: decision-like states low, errors at 10 and 11

## Objective

Move the two error classes off 2 and 3 to 10 and 11, so the low codes are free for outcomes of the question itself: 0 decided (yes under `--exit`), 1 no under `--exit`, 2 unsure (wip/xhd adds it), 3 to 9 reserved. Update the constants, the usage text, the README tables and the prose after them, the example wrapper, and the tests.

## Context

Decided with the user on 2026-09-20. Codes group by who has to act, not by where the failure was detected. A script can test `$? -ge 10` for "page someone" and treat everything below as an outcome of the question. `if decide ...; then` is unchanged: every non-zero code still lands in the else branch, so the README's advice to put the action on the yes side still holds.

The two error classes, defined by the fix:

- **10, setup or input error: you must change something locally.** Bad usage (`UsageError`), a missing or malformed `DECIDE_MODEL`, a missing key (`unavailable(.notConfigured)`), an unreadable context file, a question the model cannot take (`invalidQuestion`, `unsupported`, `contextSizeExceeded`), and a rejected key (`unauthorized`): the server reports that one, but only you can fix it.
- **11, remote error: try again later or blame the server.** `transport`, `timeout`, `rateLimited`, `overloaded`, `refused`, `guardrailViolation`, `malformedResponse`, `insufficientProbabilityQuality`, every other `unavailable` reason, `CancellationError`, and any unknown error.

Today's mapping in `Sources/DecideCore/ExitCode.swift` (wip/mfa) already draws this line; only the numbers move.

Rules that follow, for the README: `--fallback` turns 2 and 11 into 0 by printing the fallback, and with `--exit` returns the fallback's side. In a stream, 10 stops the run at once; a per-event 2 or 11 gets its error line or its fallback and the stream goes on; the final code is the highest code any event produced. That replaces the special 4.

Two alternatives were weighed and set aside: sysexits.h (64 for usage, 75 for a temporary failure) is standard but obscure, and 10 and 11 read better in a script; 11 is also the segfault signal number, which only matters to people who read signal numbers in supervisor logs.

## Design

- `Sources/DecideCore/ExitCode.swift`: `decided` stays 0; `usage` becomes `setup = 10`; `runtime` becomes `remote = 11`. Rename every use; no aliases for the old names. `code(for:)` keeps its structure, each arm naming the new constant. Messages do not change.
- `Sources/DecideCore/Decide.swift`: the two `return ExitCode.usage` lines become `ExitCode.setup`; the usage text's last line becomes `Exit codes: 0 decided, 10 setup or input error, 11 remote error.` (wip/xhd inserts `2 unsure`).
- `Examples/decide`: the missing-binary path exits 10 instead of 2.
- `README.md`, "Exit codes and errors" (lines 272 to 300 today). Replace the plain table with:

```
| Code | Decision |
|---|---|
| 0 | Decided: see stdout
| 1 | Not used
| 2 | Not decided: unsure (confidence below --min-confidence, no --fallback)
| 3-9 | Reserved for decision-like states
| 10 | Not run: setup or input error (bad usage, model or key missing, unreadable file)
| 11 | Not decided: remote error (network, timeout, rate limit, model refused)
```

  and the `--exit` table with:

```
| Code | Decision |
|---|---|
| 0 | Decided: Yes
| 1 | Decided: No
| 2 | Not decided: unsure (confidence below --min-confidence, no --fallback)
| 3-9 | Reserved for decision-like states
| 10 | Not run: setup or input error (bad usage, model or key missing, unreadable file)
| 11 | Not decided: remote error (network, timeout, rate limit, model refused)
```

  Keep the sentence "Only 0 and 1 carry an answer..." as it is. Replace the `--fallback` paragraph with: "`--fallback` turns an unsure answer (exit code 2) and a remote error (exit code 11) into decisions (exit code 0) and prints the fallback value. With `--exit` it returns the code of the fallback's side, or the fallback exit code." Replace the stream paragraph with: "In a stream, 10 stops the run at once. 2 and 11 are per event: the event gets an error line or its fallback, the stream goes on, and the final code is the highest code any event produced." Nothing else in the README changes; the examples name no code numbers.
- `DEVELOPMENT.md` and `TESTING.md` name no code numbers; no change.

## Location

- `Sources/DecideCore/ExitCode.swift`, `Sources/DecideCore/Decide.swift`
- `Examples/decide`
- `README.md`, the Appendix
- `Tests/DecideCoreTests/ExitCodeTests.swift`, `Tests/DecideCoreTests/DecideRunTests.swift`

## Tests

- `ExitCodeTests`: the table's expected codes become 10 and 11; add assertions `ExitCode.decided == 0`, `ExitCode.setup == 10`, `ExitCode.remote == 11`; add one test over the whole table that every code is 0 or at least 10, with the message "1 to 9 are reserved for decision-like states", so a future error cannot land in the low range by mistake.
- `DecideRunTests`: the five error scenarios expect 10 (no arguments, unknown flag, missing file, missing model) or 11 (timeout).
- By hand: `Examples/decide --help` with the binary moved away exits 10; the built binary with no `DECIDE_MODEL` exits 10.

## Related Issues

wip/xhd (blocked on this) adds code 2. wip/mfa and wip/ayd hold the original exit-code design notes. `--exit` and `--fallback` are unfiled features that the README rules above describe.

## Acceptance Criteria

- [ ] Usage, configuration, and file errors exit 10; model runtime errors exit 11; success exits 0. Stdout is still empty on every non-zero exit.
- [ ] Both README tables and the two paragraphs after them read as above.
- [ ] `Decide.usage` ends with the new exit-code line.
- [ ] The table test proves no error maps to 1 through 9.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean and `swift test --skip DecideLive` passes.
