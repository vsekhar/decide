---
priority: p2
type: feature
created: 2026-09-24T15:01:19-04:00
updated: 2026-09-24T15:01:19-04:00
blocked-on:
  - bpg
---

# Add --each: decide once per line of standard input, one record per event, the highest code wins

## Objective

`--each` turns a run into a stream: each line of standard input is one event, the `-` context holds that line, and the questions run once per event, in order. The README's Streaming example is the target:

```sh
cat events.jsonl | decide --context policy=@policy.txt \
                          --context-json event=- \
                          --each \
                          --questions @triage.decide \
                          --json > triage_decisions.jsonl
```

With `--json`, every event prints exactly one line, so line N of the output answers line N of the input. Without it, each event prints the same lines a single run prints. Per-event trouble does not stop the stream: an unsure event prints its empty answers or fallbacks, a remote error prints the fallbacks or, with `--json`, an error record, and stderr names the event. A setup error stops the run at once with 10. The final exit code is the highest code any event produced.

## Context

Requested by the user on 2026-09-24 after a README audit found `--context-json` and `--each` unbuilt. The README's Exit codes appendix already states the stream rule: "In a stream, 10 stops the run at once. 2 and 11 are per event: the event gets an error line or its fallback, the stream goes on, and the final code is the highest code any event produced."

Blocked on wip/bpg (`--context-json`), so the JSON parse of a context sits on one load path that the stream reuses by substituting the `-` source with each line.

How the code stands (HEAD 77f627e, plus wip/bpg):

- `Decide.run` does one run: expand, parse, the `-` once check, config files, `makeModel`, `loadState`, `Runner.decide`, print, the `Unsure:` line, exit code; and in the `catch` around `Runner.decide`, the remote-error fallback path. All of it is inline in `run`.
- `Decide.run` takes `standardInput: () throws(ConfigReadError) -> String`, a whole read, wrapped once so the once-per-run check works. `StandardInput.readToEnd()` in `StandardStreams.swift` is the real reader; tests pass `ScriptedInput`.
- `Context.readsStandardInput` says whether any source is `-`; `ContextSource.standardInput` is the case.
- `ExitCode.message(for:)` gives `Error: ...` lines; `Unsure.report` gives the `Unsure: ...` line; `PlainOutput.line`, `PlainOutput.fallbackLine`, `JSONOutput.line`, `JSONOutput.fallbackLine` print.
- `DecisionSession` is made once per run; the same session can serve every event.

## Location

- `Sources/DecideCore/StandardStreams.swift`: a line reader beside the whole reader, behind one protocol.
- `Sources/DecideCore/CommandLineParser.swift`, `Invocation.swift`: the flag and its rules.
- `Sources/DecideCore/Decide.swift`: the per-event body factored out of `run`, the stream loop, the event-numbered stderr lines, the exit code.
- `Sources/DecideCore/JSONOutput.swift`: the error record.
- `README.md`: two sentences under Streaming and the Exit codes paragraph.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `DecideRunTests.swift`, `JSONOutputTests.swift`.

## Approach

**Flag and rules.** `--each` is a run flag like `--json`, once per line, on `Invocation` as `each: Bool`. The parser refuses: `--each` with no `-` context (`--each needs a --context - or --context-json <name>=- to read events from`); `--each` with `--quiet` (`--each does not go with --quiet`); `--each` with a second `--each` (`--each was given twice`). `Decide.run` refuses `--each` with `--questions -` (`--each reads standard input as events, so --questions - cannot`), because only the run knows the expansion read stdin; it fires where the once-per-run check does, before any setup.

**Reading events.** `StandardStreams.swift` gains a protocol the run reads through:

```swift
/// Standard input as the run reads it: whole, or one event at a time.
public protocol StandardInputReading {
    /// Every byte up to end of file, as text.
    func readToEnd() throws(ConfigReadError) -> String
    /// The next line without its line ending, or nil at end of file.
    func readLine() throws(ConfigReadError) -> String?
}
```

`StandardInput` conforms. `readLine` reads raw bytes in chunks through `FileHandle.standardInput.read(upToCount:)` (the throwing one, in the same family as `readToEnd`), splits on LF, drops a trailing CR, and decodes each line as UTF-8 by hand: a line that is not UTF-8 is `.notUTF8`, a read that fails is `.unreadable`. A last line with no LF is still a line. `Decide.run`'s `standardInput` parameter becomes `some StandardInputReading` with `StandardInput()` as its default; the tests' `ScriptedInput` conforms, giving lines from its text. The once-per-run wrapper records either kind of read.

**The stream.** Factor the per-event body out of `run` into one function that takes the parsed invocation, the loaded context (every source but `-` already read to text), the session, and the streams, and returns the event's exit code; a plain run calls it once. With `--each`, after `makeModel` and after the other contexts load, the loop reads a line, skips a blank one, substitutes the `-` source with `.text(line)` (a `Context` helper), and calls the body. The `--context-json` parse then applies to the line as it would to whole stdin, so `event=-` under `--each` parses each line as JSON. Events run one at a time; the session is shared.

**Per-event outcomes.** Every stderr line from an event starts with `event N: ` (N from 1): `event 3: Unsure: question 1 (...)`, `event 3: Error: the request timed out.`

- Decided (0): the event's lines print. A yes/no answer does not set the code in a stream, so a decided event is 0 whatever it answered; each event's answer is on its line.
- Unsure without a fallback (2): the lines print with empty answers, the `Unsure:` line, the stream goes on.
- Remote error (11) with every question covered: the fallback lines print, the `Error:` line, the event counts as 0. Not covered: plain output prints nothing for the event; `--json` prints one line with an error record per question, `{"team":{"kind":"choice","error":"the request timed out."}}`, the message without its `Error: ` prefix, so the output stays one line per event; the `Error:` line; the event is 11; the stream goes on.
- Setup error (10), from the model or from an event line that is not valid JSON under `--context-json`, or not UTF-8: the `Error:` line, nothing on stdout for the event, the run stops, exit 10.

The final code is the highest any event produced: 0 when every event decided, 2 or 11 when some did not, 10 when the run stopped. An empty stream prints nothing and exits 0.

**JSON error record.** `JSONOutput` gains `errorLine(for questions: [Question], message: String) -> String`: each object is `kind` then `"error": "<message>"`, keys and ids as `line` gives them.

**Usage text.** After `--json`:

```
          --each                         Decide once per line of standard input: each line is
                                         the event the - context holds, and each event prints
                                         its own lines, one with --json. stderr names the
                                         event. Not with --quiet or --questions -.
```

**README.** Under Streaming, after the example: "Each line of standard input is one event, and the `-` context holds it. With `--json`, every event prints one line, so line N of the output answers line N of the input, and an event the model server failed prints an error record. Blank lines are skipped." Replace the stream paragraph under Exit codes with: "In a stream, 10 stops the run at once. 2 and 11 are per event: the event prints its empty answers or its fallbacks, or with `--json` an error record, stderr names the event, the stream goes on, and the final code is the highest code any event produced. A decided event counts as 0, so one yes/no question does not answer with the exit code in a stream."

## Out of Scope

- Running events in parallel, or batching several events into one request.
- A per-event timeout, a retry, or a stop-after-N-errors switch.
- Any change to `--context-json` beyond calling its parse per event.

## Tests

- Parser: `--each` sets `each`; twice, with `--quiet`, and without a `-` context each throw their message; `--each` with `--context-json event=-` and with `--context -` parse.
- `StandardInput.readLine`: not unit-testable against the real descriptor here; the verifier drives the binary with `printf` through a pipe: LF, CRLF, a last line with no LF, a blank line, and a line that is not UTF-8.
- JSONOutput: `errorLine` for a named choice and an unnamed verdict.
- Run (`ScriptedInput` with several lines, `ScriptedModel` whose closure answers from the request's state or throws on a chosen event): three text events under `--context event=-` print three answers in order and exit 0, and the model saw each line as `.text`; the same with `--json` prints three JSON lines; `--context-json event=-` with three JSON lines sends each as `.object` and a fourth line that is not JSON stops the run with `event 4: Error: context "event" is not valid JSON`, exit 10, three lines printed; an unsure event prints an empty answer and `event 2: Unsure: ...`, the stream goes on, exit 2; a remote error on event 2 with fallbacks prints them and exits 0, and without them prints nothing for the event in plain output and an error record with `--json`, `event 2: Error: the request timed out.`, exit 11; an `unauthorized` on event 2 stops with exit 10 after event 1 printed; blank lines are skipped; CRLF lines lose their CR; an empty stream prints nothing and exits 0; a one-yes/no-question stream whose events answer no still exits 0; `--each --questions -` exits 10 with its message; the usage text lists `--each`.
- No live test: the wire does not change.

## Related Issues

- Blocked on wip/bpg (`--context-json`).
- wip/4c6 (`-` reads stdin whole; the once-per-run rule), wip/oin (fallbacks and the remote-error path this reuses per event), wip/a0g (the empty answer and the `Unsure:` line).

## Acceptance Criteria

- [ ] The README's Streaming example runs against a scripted model: one JSON line per event, in order, from `--context-json event=-` with `--each`.
- [ ] A decided, an unsure, and a remote-error event each print as specified, stderr names the event, the stream goes on, and the final code is the highest code any event produced; a setup error stops the run with 10.
- [ ] `--each` with no `-` context, with `--quiet`, or with `--questions -` exits 10 with its message.
- [ ] Lines end at LF or CRLF, blank lines are skipped, a last line without LF counts, and a line that is not UTF-8 stops the run with 10.
- [ ] `--help` and the README describe `--each`, and the Exit codes paragraph matches the code.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.
