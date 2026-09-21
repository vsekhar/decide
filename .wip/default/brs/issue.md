---
priority: p1
type: task
created: 2026-09-21T02:18:44-04:00
updated: 2026-09-21T02:18:44-04:00
---

# One yes/no question answers with its exit code, 0 yes and 1 no; --exit becomes --quiet

## Objective

A run with exactly one yes/no question answers with its exit code as well as on stdout: 0 for yes, 1 for no, like `grep`. Every other run keeps 0 for decided. `--exit` goes away; `--quiet` (`-q`) takes its place and only drops the printed answer. The README's `if decide ...` idiom then works with or without a flag.

## Context

Decided with the user on 2026-09-21. The README's Yes or no section scripts a verdict with `if decide --context="$body" "Is this message spam?" --exit; then mv "$file" spam/; fi`. Drop `--exit` and every decision exits 0, so every message moves to spam. The failure is silent and acts on every input. No runtime check can catch it: a process cannot tell whether it runs inside an `if`, and stdout is the terminal in both cases. The fix has to be in the default.

Options weighed:

- A. Keep 0 for every decision and fix the docs. The trap stays armed.
- B. One yes/no question: the exit code is the answer, always. Chosen. It is how `grep`, `diff`, and `cmp` behave, and it lands on the scheme wip/fjj set up, where 1 is already reserved for no. The two failure modes swap: today a dropped flag fails wrong; under B a dropped `|| true` under `set -e` fails stop, at the first no, where the author sees it.
- C. A yes/no question must say how it reports (`--exit` or `--print`), else a usage error. Safest, but it taxes the simplest example.
- D. B plus a `--print` opt-out that restores 0 on no. Held in reserve; add it only if the `set -e` capture case bites.

What B costs: capturing a single verdict under `set -e` needs `x=$(decide ...) || true`, or better `if answer=$(decide ...); then`, which gives the value and the truth in one call. Errors and unsure answers land on the else side, so the advice to put the action on the yes side holds. Choices, ratings, and batches are unchanged, because one code cannot carry several answers.

`--exit` no longer changes the code, so the only thing left for it is to silence stdout. That is `grep -q`. Rename it `--quiet`, short `-q`, rather than keep a name that promises what the default now does. `--fallback` is unfiled; the README rules that mention it change wording only.

The rule, in one sentence: one yes/no question, the exit code is the answer, like grep; otherwise 0 means decided and the answers are on stdout.

## Design

- `ExitCode`: `public static let no: Int32 = 1`, doc `/// The one yes/no question answered no.` The enum doc becomes: 0 is a decision, and yes when the run has one yes/no question; 1 is no in that case; 2 is unsure; 3 to 9 are reserved; errors start at 10. `code(for:)` is unchanged: `no` is not an error and no error maps to it. The `constants` test pins 1; `reservedRange` stays as it is.
- `Invocation` gains `public var quiet: Bool` with a default of `false` in the initializer. `CommandLineParser` accepts `--quiet` and `-q` anywhere, at most once (`--quiet was given twice`). After the walk, `quiet` with anything other than exactly one yes/no question is `--quiet needs exactly one yes/no question`, because the answer would be lost.
- `Decide.run`: after the outcomes come back, when `invocation.questions.count == 1` and that question's kind is `.verdict(yes:no:)`, the code is `ExitCode.decided` when `outcome.answer == yes.id`, else `ExitCode.no`. Any other run returns `decided`. Answers print to stdout unless `quiet`. Unsure and errors are unchanged: 2, 10, 11, nothing on stdout.
- `Decide.usage`: the flag list gains `--quiet, -q             Print no answer. Only with one yes/no question.` before `--help`. The exit line becomes `Exit codes: 0 decided or yes, 1 no (one yes/no question), 2 unsure, 10 setup or input error, 11 remote error.`
- `README.md`:
  - Yes or no: the `if` example loses `--exit` and gains `-q`; a sentence before it says one yes/no question also answers with its exit code, 0 for yes and 1 for no, like `grep`, and `-q` drops the printed answer. A second example shows `if answer=$(decide ...); then` with a note that a no is exit 1, so a capture under `set -e` needs the `if` or `|| true`.
  - Errors: `--exit --fallback false` becomes `-q --fallback false`.
  - Exit codes and errors: the second table's lead-in becomes "When the run has one yes/no question, the exit code carries the answer as well:"; the rows stay. "A script that branches on `--exit`" becomes "A script that branches on the exit code". The `--fallback` paragraph: "With one yes/no question it returns the code of the fallback's side" in place of "With `--exit` it returns...". No other mention of `--exit` remains.
- `TESTING.md`, "What the suite cannot see": the invariant becomes "on every exit of 2 or more, stdout must be empty", since a no now exits 1 with the no value on stdout. The hand check gains a second line: one yes/no question exits 0 or 1 with one line on stdout, and `-q` with an empty stdout.
- `Examples/`: unchanged; no script uses `--exit`, and `ticket.sh` has three questions.

## Location

- `Sources/DecideCore/ExitCode.swift`, `Invocation.swift`, `CommandLineParser.swift`, `Decide.swift`
- `README.md`, `TESTING.md`
- `Tests/DecideCoreTests/ExitCodeTests.swift`, `CommandLineParserTests.swift`, `DecideRunTests.swift`

## Tests

Swift Testing, `ScriptedModel`, no network:

- Parser: `--quiet` and `-q` set `quiet`, anywhere on the line, on a single verdict; absent is `false`; a repeat throws; `--quiet` with a choice question, with a rating, or with two questions throws `--quiet needs exactly one yes/no question`; `--option -q` still makes an option with id `-q` (a flag value is verbatim, as today).
- Run: one bare question with P(yes) 0.8 prints `yes` and returns 0; with 0.2 prints `no` and returns 1; custom values print the value with the same codes; `-q` prints nothing and returns 0 or 1; one verdict under a bar it misses returns 2 with an empty stdout; a single choice question returns 0; the three-question batch returns 0 with three lines and no `--quiet`.
- ExitCode: `ExitCode.no == 1`; the error table still maps nothing to 1.
- By hand: `decide --context "free money" "Is this message spam?" -q; echo $?` prints 0 or 1 and nothing else; the built binary's `--help` ends with the new exit line.

## Related Issues

wip/fjj set the code scheme and reserved 1 for no; wip/h9x added the verdict kind; wip/xhd added unsure (2) and `--min-confidence`. `--fallback` is unfiled; its README rules change wording only. No blockers.

## Acceptance Criteria

- [ ] `if decide --context "$body" "Is this message spam?"; then ...; fi` runs the body only on a yes, with or without `-q`; a no exits 1 with the no value on stdout, and `-q` leaves stdout empty.
- [ ] A choice, a rating, or any batch still exits 0 when decided, with one answer per line.
- [ ] `--quiet` on anything but one yes/no question exits 10 with a message that says so; `--exit` is an unknown flag.
- [ ] README and TESTING.md name no `--exit`, and the stdout invariant reads "exit of 2 or more".
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, `swift test --skip DecideLive` passes, and `swift test --filter DecideLive` passes with a key.
