---
priority: p2
type: feature
created: 2026-09-23T00:50:20-04:00
updated: 2026-09-23T02:40:02-04:00
---

# Named contexts: several --context name=... flags become one JSON object state

# Named contexts: several --context name=... flags become one JSON object state

## Objective

`decide --context ticket=@ticket.txt --context refund_policy=@refund_policy.txt "Should we issue a refund?" --yes yes="Allowed by refund_policy and requested in ticket" --no no` sends the model one JSON object, `{"ticket": "<the file's text>", "refund_policy": "<the file's text>"}`, and prints its answer. When a line holds more than one `--context`, every one must be named. A single named context is allowed and is a one-field object. A single unnamed `--context` behaves exactly as today. A repeated name, an invalid name, or a mix of named and unnamed contexts is a usage error.

## Context

Requested by the user on 2026-09-23, with two decisions taken the same day: a lone named context is allowed and gives a one-field object, so a question can refer to the name the same way whether there is one context or five; and a value is named when the text before its first `=` is an identifier. The README's "Compose context from multiple sources" example (the spec) and its question-file examples already show the syntax and how questions refer to names in prose. wip/chc listed named contexts as out of scope; wip/5gr made the one context optional and noted that composite "will later change the type, not the optionality", which this issue does.

Today: `CommandLineParser` collects one `ContextSource` (`.text` or `.file`) and throws `--context was given twice` on a second. `Decide.run` loads it with `loadContext(_:stderr:)` into a `String?`, and `Runner.decide(_:about: String?, using:)` calls `session.decide(questionnaire, about:)` or `session.decide(questionnaire)`. The library's `State` (`DecisionModels/State.swift`) has `.text(String)` and `.object([String: State])`, encodes an object as a plain JSON object, and conforms to `StateRepresentable`, so `session.decide(questionnaire, about: someState)` already works.

## Location

- `Sources/DecideCore/Invocation.swift`: the context type.
- `Sources/DecideCore/CommandLineParser.swift`: collecting and checking `--context` values.
- `Sources/DecideCore/Runner.swift`: `decide` takes a `State?`.
- `Sources/DecideCore/Decide.swift`: loading named contexts, assembling the object, the usage text.
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `RunnerTests.swift`, `DecideRunTests.swift`, `DecideLiveTests.swift`.
- `README.md`: no change; the composite example is already there and this issue makes it true.

## Approach

**Types.** `ContextSource` stays. Add `public struct NamedContext: Sendable, Equatable { public let name: String; public let source: ContextSource }` with a public init, and `public enum Context: Sendable, Equatable { case single(ContextSource); case named([NamedContext]) }`. `Invocation.context` becomes `Context?`; nil is still no context. The named array keeps command-line order, for messages and for a deterministic load order; the object the model sees is keyed by name. Doc comments say what each case means and that `.named` with one element is a one-field object.

**Parser.** Collect every `--context` value in order (`flagValue` as today; drop the "given twice" guard). Classify each value: take the text before the first `=`. When there is no `=`, or that text is empty, or it holds whitespace, the value is plain text or `@path` as today. Otherwise the text is a name attempt: a valid name is a letter or `_` followed by letters, digits, or `_` (ASCII); a valid name makes a named context whose source is the rest after the `=`, read as today (`@path` is a file, `@` alone is `--context <name>=@ names no file`, anything else is text); an invalid attempt throws `--context name "1st" is not valid: a letter or _ then letters, digits, or _`. So `ticket=@ticket.txt` and `policy=some text` are named; `x = 1` and `=foo` are plain text; `1st=@f.txt` and `a.b=@f.txt` are errors. An empty rest (`ticket=`) throws `--context ticket= has no value`, since a blank named context is a typo more often than a wish. After the loop: no values gives nil; one unnamed gives `.single`; one named gives `.named([it])`; two or more where any is unnamed throws `every --context needs a name when there is more than one, like --context ticket=@ticket.txt`; a name used twice throws `--context names "ticket" twice`. The `parse` doc comment gains two sentences on names. `--context was given twice` goes away, and its test with it.

**Runner.** `decide(_ questions: [Question], about state: State?, using session: DecisionSession)`. A non-nil state goes to `session.decide(questionnaire, about: state)`; nil to `session.decide(questionnaire)`. Doc comment: the state is the text of one context, or an object of named ones, or nothing. Existing callers pass `.text(...)`.

**Run.** In `Decide.run`, replace the `String?` context with a `State?`: `.single(source)` loads as today into `.text`; `.named(list)` loads each source in order with the same `loadContext`, the first failure returning exit 10 with today's "cannot read context file" message, and assembles `.object(Dictionary(uniqueKeysWithValues: ...))`, every field a `.text`. Keep the model built before the contexts load. The reading of files is the only I/O; a private `loadState(_ context: Context, stderr:) -> State?` keeps `run` short.

**Usage text.** After the two `--context` lines add, in the current column:

```
  --context <name>=<text>        A named context, as a field of one JSON object.
  --context <name>=@<path>       A named context from a file. With more than one
                                 --context, every one needs a name.
```

## Tests

- Parser: one unnamed value is `.single` as before, both `.text` and `.file`; one named file is `.named([NamedContext(name: "ticket", source: .file("ticket.txt"))])`; the README's two-file example gives `.named` in command-line order; a named text value; `x = 1` and `=foo` are `.single(.text(...))`; `1st=@f.txt` and `a.b=@f.txt` throw the invalid-name message; `ticket=` throws; `ticket=@` throws the names-no-file message; `a=@x` then `@y`, and `@y` then `a=@x`, both throw the every-needs-a-name message; `a=@x` twice throws the twice message; three named contexts parse; `--context=ticket=@t.txt` (the `--flag=value` form) parses as named `ticket`.
- Runner: `about: .object(["ticket": .text("t"), "refund_policy": .text("p")])` sends a request whose `state` is that object; `about: .text(...)` and `about: nil` still send `.text` and nil (update the existing recording tests).
- DecideRun: two named `@file` contexts reach the model as `.object` with both texts (temp files, as `fileContext` does); one named context reaches it as a one-field object; a named file that is missing exits 10, names the path, prints nothing on stdout, and reaches no model; a named and an unnamed context together exit 10 with the usage message and the usage text; the unnamed `@file` and text cases stay as they are.
- DecideLive, one round trip: the README's refund example with inline texts so no files are needed, a policy "Refunds are allowed within 30 days of delivery." and a ticket "I received the shoes five days ago and want my money back. Order 4471.", the question "Should we issue a refund?" with `--yes yes="Allowed by refund_policy and requested in ticket"` and `--no no`; expect `yes`, exit 0, empty stderr. Only a live call proves that the object state crosses the wire and that the model reads the named fields.

## Design Decisions

- Named means object, always: one named context is `{"name": "..."}`, so a question's reference to the name has a referent in every case. Decided with the user 2026-09-23.
- The name rule keeps today's plain text safe: a value is a name attempt only when the text before its first `=` is non-empty and holds no whitespace. That makes an invalid name an error, as asked, without turning `x = 1` into one. The one edge, plain text that begins with `word=`, needs a file. Decided with the user 2026-09-23.
- Names are ASCII identifiers because questions mention them in prose and JSON keys carry them verbatim. Hyphens are out; the user chose identifiers over the config file's key set.
- Every named value is a text. JSON values (`--context-json`) and stdin (`name=-`) from the README's streaming example are later features; `NamedContext.source` is where they will plug in.
- A blank named value is an error, unlike a blank unnamed `--context ""`, which stays accepted for compatibility.

## Related Issues

wip/5gr (optional context; its note anticipated this type change), wip/chc (listed named contexts as out of scope), wip/79i (per-run `--model`; independent, both touch the parser and `Decide.run`, so land one before starting the other).

## Acceptance Criteria

- [ ] The README's composite example parses, loads both files, and sends the model one object keyed by the two names; the live test gets `yes` from the real model.
- [ ] One unnamed `--context` behaves exactly as before, in both value forms; one named `--context` sends a one-field object.
- [ ] More than one `--context` with any unnamed one, a repeated name, an invalid name, a blank named value, and `<name>=@` each exit 10 with the message above and nothing on stdout.
- [ ] `--help` lists the named forms.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-23 02:21:26-04:00 @ git:f6f9edf+local_

Design record (2026-09-23), the decisions the Approach left open. Implemented as written there, plus:

1. Parser shape. The loop collects each --context value as a private ContextEntry (.unnamed(ContextSource) or .named(NamedContext)), in order. A private contextEntry(from:) classifies one value; a private context(from: [ContextEntry]) turns the list into Context? after the loop. A private isName(_:) holds the identifier rule, on Character: first is ASCII and (letter or _), the rest ASCII and (letter, digit, or _).
2. Error precedence, after the loop: the mix check (every --context needs a name...) runs before the repeated-name check, so `a=@x a=@y @z` reports the mix. Both messages are the issue's, verbatim.
3. contextSource(from:) takes a second parameter, the text the names-no-file message quotes before the @: "--context " for an unnamed value and "--context ticket=" for a named one. So the two messages are `--context @ names no file` and `--context ticket=@ names no file` from one function.
4. A value whose text before the first = is non-empty and whitespace-free is a name attempt even when it is not identifier-like: `@ticket.txt=x` and `http://x=y` throw the invalid-name error. That is the decided rule's consequence; such text needs a file.
5. Decide.loadState builds the object by assignment in a loop (fields[name] = .text(text)), not Dictionary(uniqueKeysWithValues:), because Invocation is public with a public init and a trap on a repeated name is worse than last-wins. Context.named's doc says the parser keeps names unique and the run keeps the last of a repeat.
6. The usage line and the "about one context or none" sentence stay; only the two flag lines from the Approach are added.
7. RunnerTests.context becomes a State (.text of the same sentence) so the ~25 call sites stay `about: Self.context`; the oneRequest expectation becomes `request.state == Self.context`.
8. Existing parser tests wrap the old context values in .single(...). The twoContexts test is removed with its message.

---

_📝 Noted on 2026-09-23 02:30:54-04:00 @ git:f6f9edf+local_

Implementation (2026-09-23): a worker implemented the Approach and the design record as written; no open question came up. Points beyond the record:
- Long messages (the mix error) use the repo's `"""` block with a `\` line break, as ExitCode.swift and ConfigFiles.swift do; the run-time string is one line and the tests match it with the same block.
- contextEntry(from:) uses two guards that share one `.unnamed` return (no `=`; then empty or whitespace name), because an irrefutable `case let` in a guard risks a warning under -warnings-as-errors.
- The post-loop call is `try Self.context(from: contexts)`, qualified because the local is also named `context`.
- loadState carries a comment on why it assigns into the dictionary instead of Dictionary(uniqueKeysWithValues:).
Checks: build with -warnings-as-errors clean; `swift test --skip DecideLive` 254 tests pass; the live suite passed once, 3 tests, the new refund test answered `yes`.
Noticed, out of scope: the README composite example (line ~72) ends its `--yes` line with a trailing `\` and then `no` on its own line, so a shell would read `no` as a second question. Either the `\` is a typo before the output `no`, or `--no no` is missing.

---

_📝 Noted on 2026-09-23 02:40:02-04:00 @ git:f6f9edf+local_

Summary (2026-09-23): done. `--context name=value` parses to a named context; several make one JSON object state, one named makes a one-field object, one unnamed stays a text. Types: Context (.single/.named), NamedContext. Parser: ContextEntry, contextEntry(from:), isName, contextSource(from:as:), context(from:); the five new usage errors, verbatim from the issue; `--context was given twice` removed. Runner.decide takes State?. Decide.loadState assembles the object; usage lists the two named forms.
Verifier: all five acceptance criteria hold, no blockers. Acted on two notes: added tests that `@t.txt=x` and `http://x=y` are invalid names (a mutant that treats @:/ prefixes as text kills exactly those two rows), and the parse doc now says a bad name is an error, not text. Left as notes: a line with only contexts and no question now reports "no question given" before the mix check; NamedContext.init has no doc comment, like every memberwise init in the file; Context.named([]) would send {} but the parser never builds it.
Final: warnings-as-errors build clean; `swift test` with .env sourced, 257 tests in 8 suites passed, live included.
