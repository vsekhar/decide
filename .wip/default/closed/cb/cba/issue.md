---
priority: p2
type: feature
created: 2026-09-24T15:01:19-04:00
updated: 2026-09-27T15:00:13-04:00
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
- [ ] A decided, an unsure, a remote-error, and a bad-line event (not valid JSON, or not UTF-8) each print as specified, stderr names the input line, the stream goes on, and the final code is the highest code any event produced; a setup error from the model stops the run at once.
- [ ] `--each` with no `-` context, with `--quiet`, or with `--questions -` exits 10 with its message.
- [ ] Lines end at LF or CRLF, blank lines are skipped but still counted in the line number, a last line without LF counts, and a line that is not UTF-8 is a per-event error with code 10.
- [ ] `--help` and the README describe `--each`, and the Exit codes paragraph matches the code.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-27 14:36:54-04:00 @ git:8c5fe99+local_

Design record (2026-09-27), read with the Approach. Where they differ, this note wins; the two acceptance criteria it changes are already patched in the description.

## User decisions, 2026-09-27

1. Blank lines are skipped.
2. A bad event line is a per-event error, not a stop.
3. Plain output in a stream is best effort: humans read stderr, and `--json` is the strict machine-readable path.

## Decisions past the Approach

A. **stderr names the input line, not an event count.** Every stderr line of an event starts with `line N: `, N the input line number from 1, blank lines counted, so the message points at the file. `event N` is dropped. A line is blank when every character is whitespace.

B. **Three kinds of per-event trouble.** Unsure (2) and remote error (11) as the Approach says, plus a bad line (10): text that is not valid JSON under `--context-json`, or bytes that are not UTF-8. A bad line prints nothing on stdout without `--json` and an error record with it; stderr prints `line N: Error: context "event" is not valid JSON`, `line N: Error: the context is not valid JSON`, or `line N: Error: the line is not valid UTF-8`; the event's code is 10; no fallback prints, because a fallback covers an unsure answer or a failed server, not bad input. Two things stop the run: a model error whose code is `ExitCode.setup` (`unauthorized` and the like), which prints `line N: Error: ...` and stops; and standard input that does not read (`.unreadable`), which prints `Error: cannot read standard input` with no prefix, because no line was read. The final code is the highest any event produced, the stopping error's included (`max`). An empty stream prints nothing and exits 0.

C. **Loading errors become a typed error, so the stream can print them with a prefix and put them in a record.** `loadState`, `loadContext`, and `state(of:as:named:stderr:)` stop printing and stop taking `stderr`; they throw `ContextLoadError`, internal, in Decide.swift:
```swift
/// Why a context did not load: its file or standard input did not read, or
/// a `.json` context's text is not valid JSON.
enum ContextLoadError: Error, Equatable {
    /// A context file that does not read, with the path and the system's reason.
    case unreadableFile(path: String, reason: String)
    /// Standard input that does not read.
    case unreadableInput
    /// Standard input that is not UTF-8.
    case inputNotUTF8
    /// An event line that is not UTF-8, under `--each`.
    case lineNotUTF8
    /// A `.json` context whose text is not valid JSON. `name` is nil for an
    /// unnamed context.
    case notJSON(name: String?)

    /// The message, after `Error: `.
    var message: String {
        switch self {
        case .unreadableFile(let path, let reason): "cannot read context file \"\(path)\": \(reason)"
        case .unreadableInput: "cannot read standard input"
        case .inputNotUTF8: "standard input is not valid UTF-8"
        case .lineNotUTF8: "the line is not valid UTF-8"
        case .notJSON(let name): (name.map { "context \"\($0)\"" } ?? "the context") + " is not valid JSON"
        }
    }
}
```
`ExitCode.message(for:)` gains `case let error as ContextLoadError: "Error: \(error.message)"` and `code(for:)` gains `case is ContextLoadError: setup`, both before the `default`. Every message text is byte-identical to today's. The single run prints `ExitCode.message(for: error)` and returns `ExitCode.setup` where it printed nil-returns before. `ExitCode` also gains:
```swift
    /// The message without its `Error: ` prefix, for a `--json` error
    /// record. Every message `message(for:)` gives starts with that prefix.
    static func reason(for error: any Error) -> String {
        String(message(for: error).dropFirst("Error: ".count))
    }
```

D. **Files read once.** `Decide.readingFiles(in:)` gives the context with every `.file` source read to `.text`, and leaves `.text` and `.standardInput` as they are; it throws `ContextLoadError.unreadableFile`. The stream calls it once before the first event. `Context.replacingStandardInput(with:)` in Invocation.swift, pure, gives the context with every `.standardInput` source replaced by `.text(text)`. Per event the stream calls `loadState` on `base.replacingStandardInput(with: line)`, which can throw only `.notJSON`; the stdin closure it takes is never reached.

E. **The line reader.** In StandardStreams.swift:
```swift
/// Standard input as the run reads it: whole, or one line at a time. A run
/// does one or the other, never both.
public protocol StandardInputReading {
    /// Every byte up to end of file, as text. A descriptor that does not
    /// read is `.unreadable`, and bytes that are not UTF-8 are `.notUTF8`.
    func readToEnd() throws(ConfigReadError) -> String
    /// The next line without its line ending, or nil at end of file. A line
    /// ends at a line feed, and a carriage return before it is dropped. A
    /// last line with no line feed is still a line. A descriptor that does
    /// not read is `.unreadable`. A line that is not UTF-8 is `.notUTF8`,
    /// and the reader has moved past it, so the next call gives the next
    /// line.
    func readLine() throws(ConfigReadError) -> String?
}
```
`StandardInput` becomes `public final class StandardInput: StandardInputReading` with a `[UInt8]` buffer and an `atEnd` flag (a class, because the protocol's methods do not mutate and the run holds the reader as `any StandardInputReading`). `readToEnd` stays as it is. `readLine` loops: when the buffer holds a line feed, take the bytes before it, drop them and the line feed from the buffer, and decode; else when `atEnd`, give the rest as the last line, or nil when the buffer is empty; else read a chunk with `FileHandle.standardInput.read(upToCount: 65536)` (throwing; a throw is `.unreadable`; nil or an empty chunk sets `atEnd`) and append it. Decoding drops one trailing carriage return, then `String(validating: bytes, as: UTF8.self)`; nil is `.notUTF8`. The buffer has already moved past the line when it throws. `read(upToCount:)` gives what the pipe holds, so a line is decided as soon as its line feed arrives, not at end of file.

`Decide.run`'s parameter becomes `standardInput: any StandardInputReading = StandardInput()`. The recording wrapper inside `run` calls `standardInput.readToEnd()`. `QuestionFile.expanding` keeps its closure parameter. The executable needs no change.

F. **The per-event body**, factored out of `run`:
```swift
    /// Runs the questions about the state and prints the answers: the whole
    /// of a plain run, or one event of a stream. `line` is the event's input
    /// line number in a stream, and nil in a plain run. Every stderr line of
    /// an event starts with `line N: `. Returns the exit code. A plain run
    /// gives the answer's code, as `run` describes. In a stream a decided
    /// event is 0 whatever it answered, so is a remote error every fallback
    /// covers, and a model error whose code is `ExitCode.setup` returns that
    /// code, which stops the stream. A remote error no fallback covers prints
    /// an error record under `--json` in a stream, so the event still prints
    /// one line, and nothing in a plain run.
    private static func decide(
        _ invocation: Invocation,
        about state: State?,
        using session: DecisionSession,
        line: Int?,
        stdout: inout some TextOutputStream,
        stderr: inout some TextOutputStream
    ) async -> Int32
```
It holds what `run` holds today from `let outcomes: [Outcome]` to its end, with `let prefix = line.map { "line \($0): " } ?? ""` before every stderr print (`prefix + ExitCode.message(for: error)`, `prefix + Unsure.report(unsure)`), the `--json` error record on the remote path when `line != nil` and not every question has a fallback, and `line == nil ? exitCode(for:questions:) : ExitCode.decided` at both returns that give the answer's code. The plain run calls it with `line: nil`.

G. **The stream**, `Decide.stream(_:model:standardInput:stdout:stderr:)`, called from `run` right after the model is made when `invocation.each`:
- `guard let context = invocation.context` else print `ExitCode.message(for: UsageError(CommandLineParser.eachNeedsStandardInput))` and return setup (the parser refuses this; the guard keeps `Invocation`, which is public, honest).
- `base = try readingFiles(in: context)`; a throw prints its message and returns setup.
- One `DecisionSession(model:)` for every event; `highest = ExitCode.decided`; `number = 0`.
- Loop: read a line. nil ends the loop. `.unreadable` prints `ExitCode.message(for: ContextLoadError.unreadableInput)` and returns `max(highest, setup)`. `.notUTF8` counts the line and reports a bad line with `.lineNotUTF8`. A read line counts; a blank one is skipped; else `loadState(base.replacingStandardInput(with: line), ...)`, and a throw reports a bad line with that error; else `code = await decide(..., line: number, ...)`, `highest = max(highest, code)`, and `code == setup` returns `highest`.
- Reporting a bad line: `line N: ` + `ExitCode.message(for: error)` on stderr; with `--json`, `JSONOutput.errorLine(for: invocation.questions, message: ExitCode.reason(for: error))` on stdout; `highest = max(highest, setup)`; the loop goes on.
- After the loop, return `highest`.

H. **The error record.** In JSONOutput.swift:
```swift
    /// The line for an event the run could not decide and no fallback
    /// covers: each object has `kind` and then `error`, the message without
    /// its `Error: ` prefix, and no other key, because there is no answer.
    /// Keys and ids as `line(for:outcomes:)` gives them. A stream prints it
    /// under `--json`, so every event still prints one line.
    public static func errorLine(for questions: [Question], message: String) -> String
```
Example: `{"team":{"kind":"choice","error":"the request timed out."}}` and for an unnamed verdict `{"q1":{"kind":"verdict","error":"context \"event\" is not valid JSON"}}`.

I. **The flag.** `Invocation.each: Bool`, after `json`, default false, documented: "Decide once per line of standard input, from `--each`. A `-` context holds each line. Never with `quiet`." The parser: `--each` twice is `--each was given twice`; after the questions are built and `context` is made, `each && quiet` is `--each does not go with --quiet`, then `each` with `context?.readsStandardInput != true` is `CommandLineParser.eachNeedsStandardInput`, a `static let` like `standardInputTwice`, with the text `--each needs a --context - or --context-json <name>=- to read events from`. `parse`'s doc comment gains, after the `--context-json` sentence: "`--each` runs the questions once per line of standard input, which a `-` context must hold, and does not go with `--quiet`." No check for `--each` with `--questions -` is added to `run`: with no `-` context the parser refuses the line for want of one, and with a `-` context the existing `- was given twice` rule fires first, so no line with both can pass. The usage text still says "Not with --quiet or --questions -", which is true.

J. **Usage text**, after the `--json` entry, flag at column 2, description at column 33 like its neighbours:
```
  --each                         Decide once per line of standard input: each line is
                                 the event the - context holds, and each event prints
                                 its own lines, one with --json. Blank lines are
                                 skipped, and stderr names the input line. Not with
                                 --quiet or --questions -.
```
The last usage line gains a third sentence: `With --each, the final code is the highest any event produced.` The `run` doc comment gains: "`--each` runs the questions once per line of standard input, which the `-` context holds; each event prints its own lines, stderr names the input line, and the code is the highest any event produced."

K. **README.** Under Streaming, after the example block, one paragraph:

"Each line of standard input is one event, and the `-` context holds it. Blank lines are skipped. With `--json`, every event prints one line, so line N of the output answers the Nth non-blank line of the input; an event the model server failed, or a line that is not valid JSON, prints an error record. Without `--json`, an event prints the lines a single run prints, and an event with an error prints nothing, so read stderr, which names the input line, and use `--json` for output a program reads."

Under Exit codes, replace the paragraph that starts "In a stream, 10 stops the run at once." with:

"In a stream, a setup error stops the run at once. 2, 10, and 11 are per event: an unsure event prints its empty answers or its fallbacks; an event the model server failed prints its fallbacks, or an error record with `--json`; a line that is not valid JSON or UTF-8 prints an error record with `--json` and nothing without; stderr names the input line; the stream goes on; and the final code is the highest code any event produced. A decided event counts as 0, so one yes/no question does not answer with the exit code in a stream."

L. **TESTING.md**, at the end of "What the suite cannot see":

"A stream is the exception: stdout holds every decided event's lines while the final code may be 2, 10, or 11. The line reader reads the real descriptor, so no unit test covers it; this drives the binary through a pipe with no key and no network call, because no line parses. Expect four error records on stdout for lines 1, 2, 4, and 5, the blank line 3 skipped, four `line N: Error:` lines on stderr with line 4 not valid UTF-8, and exit 10:

```sh
printf 'a\r\nb\n\n\xff\nc' | "$bin" --model typesafe:x --api-key k \
  --context-json event=- --each "Q?" --option a --option b --json; echo $?
```"

M. **Test double.** `ScriptedInput` conforms to `StandardInputReading`. `init(_ text:)` keeps whole reads as now and also splits the text into lines the way the real reader does: at each line feed, a carriage return before it dropped, a last line with no line feed counted, and no extra empty line after a final line feed. `init(lines: [Result<String, ConfigReadError>])` scripts each line, so one can be `.failure(.notUTF8)`. `readLine` gives the next scripted line, throws its failure, and gives nil at the end; `reads` counts every call of either method.

---

_📝 Noted on 2026-09-27 14:53:03-04:00 @ git:8c5fe99+local_

Design record addendum (2026-09-27), after verification. Two changes to the record above.

N. **The reader uses `read(2)`, not `FileHandle.read(upToCount:)`.** The verifier timed `(printf 'x\n'; sleep 4; printf 'y\n') | decide --each ...`: both stderr lines arrived at end of file. Foundation's `read(upToCount:)` waits for the count or end of file on both platforms, so note E's claim that it "gives what the pipe holds" was wrong. `readLine` now fills its chunk with POSIX `read(STDIN_FILENO, ...)` into a reused `[UInt8]` of 65536 bytes: a return of -1 with `errno == EINTR` retries, any other -1 is `.unreadable`, 0 is end of file, and a positive count appends that many bytes. `readToEnd` keeps `FileHandle.readToEnd()`, which waits for end of file by design. The `readLine` doc comment says: "Reads with `read(2)`, which gives what the pipe holds as soon as any byte is ready, so a line is decided when its line feed arrives, not at end of file. `FileHandle.read(upToCount:)` would wait for the count or end of file." TESTING.md gains a timing check after the printf block, because no in-process test can see this:

"The reader must give a line as soon as it arrives, not at end of file. This pipe writes two lines three seconds apart, so the two stderr lines must carry timestamps three seconds apart:

```sh
(printf 'a\n'; sleep 3; printf 'b\n') | "$bin" --model typesafe:x --api-key k \
  --context-json event=- --each "Q?" --option a --option b 2>&1 >/dev/null \
  | while IFS= read -r line; do echo "$(date +%s) $line"; done
```"

O. **A context too large for the model is the event's error, not the run's.** `DecisionError.contextSizeExceeded` has code 10, but it depends on the event's size, so in a stream it is per event like a bad line: nothing on stdout without `--json`, an error record with it, `line N: Error: the context is too large for the model.` on stderr, the event's code is 10, no fallback prints, and the stream goes on. Every other model error with code 10 (`unauthorized`, `unavailable(.notConfigured)`, `invalidQuestion`, `unsupported`) is the same for every event and stops the stream. `decide(_:about:using:line:stdout:stderr:)` therefore returns `(code: Int32, stops: Bool)`: `stops` is true only in a stream, for a model error whose code is `ExitCode.setup` and that is not `.contextSizeExceeded`; a plain run reads `.code` alone. A private `isEventError(_:)` in Decide.swift holds the one case, documented: "Whether a model error belongs to the event alone in a stream, so the stream goes on. A context too large for the model depends on the event's size. Every other error whose code is setup is the run's, the same for every event, so it stops the stream." The README's Exit codes paragraph now reads "a line that is not valid JSON or UTF-8, or too large for the model, prints an error record with `--json` and nothing without". The usage entry does not change.

---

_📝 Noted on 2026-09-27 15:00:13-04:00 @ git:8c5fe99+local_

Summary (2026-09-27). Built by a worker from the design record and its addendum; verified in two passes, the second scoped to the addendum, with a mutant check on the per-event rule.

What landed: `StandardInputReading` and a chunked line reader on `StandardInput` (now a class) that reads with `read(2)` so a line is decided when it arrives; `Invocation.each` and the three parser refusals; `ContextLoadError` as the typed loading error, mapped in `ExitCode` with `reason(for:)` for records; `Context.replacingStandardInput(with:)` and `Decide.readingFiles(in:)`; the per-event body `decide(...)` returning `(code, stops)` and the `stream` loop; `JSONOutput.errorLine`; the usage entry and last line; the README Streaming and Exit codes paragraphs; the TESTING.md printf and timing checks. 567 offline tests pass with warnings as errors; the live suite passes; the binary checks hold.

Verification history:
- Pass 1 found the reader used `FileHandle.read(upToCount:)`, which waits for 64 KiB or end of file (timed: two lines four seconds apart both arrived at EOF). Fixed with POSIX `read(2)`; addendum item N. The TESTING.md timing pipe is the regression check, since no in-process test sees the descriptor.
- Pass 1 also noted `.contextSizeExceeded` stopped the stream though it depends on the event. Made per event; addendum item O; `eachContextTooLarge` guards it, and the mutant (`isEventError` always false) fails it while `eachUnauthorized` still passes.
- Pass 2: no blockers; three doc-comment fixes and one README sentence, done in the main context. Record K is amended: the Streaming paragraph now names every cause of an error record, "a line that is not valid JSON or UTF-8, or too large for the model".
- Left as is: the README table row for 10 says "Not run"; the stream paragraph below it explains that in a stream 10 can follow events that ran. Linux is unverified locally; CI is the check for the Glibc `read`/`errno` imports.
