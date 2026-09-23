---
priority: p2
type: feature
created: 2026-09-22T21:14:13-04:00
updated: 2026-09-22T21:14:13-04:00
blocked-on:
  - pxj
---

# Make --context optional: a bare question runs with no state

## Objective

`decide "Is Atlanta the capital of Georgia?"` prints `yes` and exits 0. A command line with questions and no `--context` runs them with no state. Every form with one `--context` works as before.

## Context

Today a run needs exactly one `--context`; the parser throws `no --context given` without it. DecisionModels 0.3.0 (issue pxj) accepts a request with no state: `DecisionSession.decide(_ questionnaire: Questionnaire, options:)` sends `state: nil`, and the providers receive an empty string. So a question that carries its own facts needs no context, and the yes/no default (no `--option` or `--level`) makes a bare question a verdict.

The README's spec also shows composite context, `--context ticket=@ticket.txt --context refund_policy=@refund_policy.txt`. That is not built: the parser rejects a second `--context` with `--context was given twice`, and no issue covers it yet. It is out of scope here. Nothing in this issue should make it harder: today a run has one `ContextSource`; this issue makes that optional, and composite will later change the type, not the optionality.

## Location

- `Sources/DecideCore/Invocation.swift`: `Invocation.context` becomes `ContextSource?`; doc comments.
- `Sources/DecideCore/CommandLineParser.swift`: drop the `no --context given` guard; the `parse` doc comment.
- `Sources/DecideCore/Runner.swift`: `decide(_:about:using:)` takes `String?` and picks the library call.
- `Sources/DecideCore/Decide.swift`: the `usage` text; the context load in `run`.
- `README.md`: one example with no context, before "Composite context".
- `Tests/DecideCoreTests/CommandLineParserTests.swift`: replace `noContext` (line 331, "A line with no --context is an error"). "A line with no question is an error" (line 352) and "A second --context is an error" (line 338) stay.
- `Tests/DecideCoreTests/RunnerTests.swift`, `DecideRunTests.swift`: a no-context case each.
- `Tests/DecideCoreTests/DecideLiveTests.swift`: one new live test.
- `Tests/DecideCoreTests/ExitCodeTests.swift` line 123 builds a `UsageError("no --context given")` only as sample text for the message format. Change the sample to a message the tool still emits, such as `no question given`.

## Approach

**Invocation.** `public var context: ContextSource?`. The initializer takes `context: ContextSource?` with no default, so every call site says what it means. Doc comment: "What one run of `decide` asks: the questions, and the context they are about, if any."

**Parser.** Remove `guard let context else { throw UsageError("no --context given") }` and pass the optional through. `no arguments given`, `no question given`, `--context needs a value`, and `--context was given twice` all stay. So `parse(["Is Atlanta the capital of Georgia?"])` returns `.run(Invocation(context: nil, questions: [one yes/no question with the default values], quiet: false))`, and `parse(["--context", "c"])` still throws `no question given`. In the `parse` doc comment say that `--context` is optional and that without it the questions run with no state.

**Runner.** `decide(_ questions: [Question], about context: String?, using session: DecisionSession)`. With a context, call `session.decide(questionnaire, about: context)`; without, `session.decide(questionnaire)`. `String?` is not `StateRepresentable`, so the branch is needed. Doc comment: a nil context sends the request with no state.

**Entry point.** In `Decide.run`, replace the `guard let context = loadContext(...)` with:

```swift
let context: String?
if let source = invocation.context {
    guard let loaded = loadContext(source, stderr: &stderr) else { return ExitCode.setup }
    context = loaded
} else {
    context = nil
}
```

`loadContext` keeps its signature; its nil still means the file did not read. The model is built before the context loads today; keep that order.

**Usage text.** The first line becomes `Usage: decide [--context <text>] "<question>" [<flags>] ["<question>" [<flags>]]...`. The paragraph: "Ask a decision model one or more questions, about one context or none. ..." with the rest unchanged. The `--context <text>` entry: "The text to judge. Optional: a question that carries its own facts needs none." Keep the `@<path>` entry.

**README.** Add before "### Composite context":

```
### No context

A question that carries its own facts needs no `--context`:

```sh
$ decide "Is Atlanta the capital of Georgia?"
yes
```
```

**Tests.**

- Parser: replace `noContext` with "A line with no --context runs the questions with no context", asserting the `.run` value above. Add `parse(["Q?", "-q"])` gives `context == nil` and `quiet == true`, since `--quiet` needs one yes/no question and a bare question is one.
- Runner: `Runner.decide(questions, about: nil, using:)` with a recording model; the request's `state` is nil. `RunnerTests` line 155 shows the recording pattern for the text case.
- DecideRun: `Decide.run(arguments: ["Is Atlanta the capital of Georgia?"], ...)` with a scripted model that answers `q1` as `.verdict(probability: 0.97)`; expect `request.state == nil`, stdout `yes\n`, stderr empty, exit 0. The same with `-q`: stdout empty, exit 0. The file's `triageModel` answers `q1` as a choice, so this needs its own scripted model; `unsureRefundModel` shows a one-answer script.
- DecideLive: add `answersWithoutContext`, running `["Is Atlanta the capital of Georgia?"]` against the real environment; expect exit 0, stdout `yes\n`, stderr empty. No doc counts requests, so nothing else changes.

## Design Decisions

- The live test earns its round trip: "should return yes" on the Atlanta question is the request's acceptance example, and only a live call proves it. The library's own live tests already pin that question on both providers, so this test proves decide's path, not the providers. Requests are cheap; the live suite's only limit is latency (TESTING.md), and one more round trip is fine.
- `--quiet` keeps its rule: exactly one yes/no question. A bare question qualifies.
- No new flag. The absence of `--context` is the whole interface.
- Composite context is out of scope (see Context).

## Related Issues

Blocked on pxj (the library bump). The library's stateless-request work is jl5 in `~/Code/DecisionModels`.

## Acceptance Criteria

- [ ] `CommandLineParser.parse(["Is Atlanta the capital of Georgia?"])` gives a run with `context == nil` and one yes/no question with the default values.
- [ ] `parse(["--context", "c"])` still throws `no question given`, and `parse(["--context", "c", "Q", "--context", "d"])` still throws `--context was given twice`.
- [ ] `Runner.decide(_:about: nil, using:)` sends a request whose `state` is nil.
- [ ] `Decide.run(arguments: ["Is Atlanta the capital of Georgia?"], ...)` with the scripted verdict model prints `yes`, exits 0, writes nothing to stderr, and the model saw `state == nil`. With `-q`, stdout is empty and the exit is 0.
- [ ] The new live test gets `yes` and exit 0 from the real model.
- [ ] `Decide.usage` shows `[--context <text>]` and says the context is optional. README has the no-context example.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.
- [ ] The binary, with `.env` sourced: `decide "Is Atlanta the capital of Georgia?"; echo $?` prints `yes` then 0. With `DECIDE_MODEL` unset it exits 10 with nothing on stdout, as TESTING.md requires.
