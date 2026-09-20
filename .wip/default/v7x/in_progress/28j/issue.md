---
priority: p2
type: task
created: 2026-09-20T18:12:54-04:00
updated: 2026-09-20T18:32:43-04:00
blocked-on:
  - s47
may-unblock:
  - ayd
---

# Parse the command line into a context source and choice questions

## Objective

A pure function from the argument list (after the program name) to an `Invocation` value: one context source and an ordered list of questions, each with its options. On bad input it throws a `UsageError` with a message that names the problem. No file or network I/O.

## Context

Part of wip/v7x. The README's Classification and Batch questions sections show the syntax:

```sh
decide --context @ticket.txt "Which team handles this ticket?" --option shipping --option billing --option returns
decide --context @ticket.txt "Q1" --option a --option b "Q2" --option c --option d
```

The grammar interleaves positional questions with the flags that belong to them. A bare word starts a new question, and `--option` attaches to the question before it. swift-argument-parser cannot express this (it collects every `--option` into one array), so the parser is hand-written. The grammar is small.

## Grammar for the skeleton

- Tokens are the argument array. The shell has already handled quoting.
- `--context VALUE` or `--context=VALUE`: the context. Exactly one. A second one is a usage error (named contexts are out of scope). If VALUE starts with `@`, the rest names a file. Otherwise VALUE is the literal text. The parser records the source only. Reading the file happens in wip/ayd.
- A token that does not start with `-` starts a new question. The token is the question's instructions.
- `--option VALUE` or `--option=VALUE`: adds an option to the current question. VALUE is `id` or `id=description`, split at the first `=`. If no question has started yet, usage error.
- `--help` or `-h`: the parser returns a help result and ignores the rest. wip/ayd prints the usage text.
- Any other token that starts with `-` is a usage error that names the token. `--level`, `--yes`, `--json`, `--questions`, and the rest of the README are out of scope for the skeleton.
- A flag at the end of the arguments with no value is a usage error.
- After the walk: no `--context` is an error, no question is an error, a question with no `--option` is an error, and duplicate option ids in one question are an error. The library's session would reject the last two before sending, but the parser's message can name the question by number and text.
- An empty argument list is a usage error. wip/ayd prints the usage text after it.

## Location

- `Sources/DecideCore/Invocation.swift`: `Invocation` (`context: ContextSource`, `questions: [Question]`), `ContextSource` (`.text(String)`, `.file(String)`), `Question` (`instructions: String`, `options: [Option]`), `Option` (`id: String`, `description: String?`).
- `Sources/DecideCore/CommandLineParser.swift`: `enum CommandLineParser { static func parse(_ arguments: [String]) throws(UsageError) -> ParseResult }` where `ParseResult` is `.help` or `.run(Invocation)`. Avoid the name `ArgumentParser`; it is the swift-argument-parser module name.
- `Sources/DecideCore/UsageError.swift`: `struct UsageError: Error { let message: String }`.

wip/wh2 also uses `Question` and `Option` and may run at the same time. Whichever issue lands first creates `Invocation.swift` with those two structs. The other adds to it.

## Tests

`Tests/DecideCoreTests/CommandLineParserTests.swift`, Swift Testing:

- The README classification example parses to one question with three options and context `.file("ticket.txt")`.
- The batch example parses to two questions, each with its own options, in order.
- `--context=@file` and `--context "text with spaces"` both work. A literal that contains `@` after the first character stays literal.
- `--option id=desc` splits at the first `=`. `--option id=a=b` gives description `a=b`.
- `--help` anywhere returns `.help`.
- Each error: no context, two contexts, no question, `--option` before a question, question without options, duplicate option ids, unknown flag, flag with no value at the end, empty arguments.
- No test touches the file system.

## Related Issues

Parent: wip/v7x. Blocked on wip/s47. wip/wh2 shares `Invocation.swift`. wip/ayd consumes the result.

## Acceptance Criteria

- [ ] The two README examples parse to the expected values.
- [ ] Each error case above throws a `UsageError` whose message names the problem.
- [ ] The parser does no I/O.
- [ ] Tests pass under `swift test`.

---

_📝 Noted on 2026-09-20 18:26:03-04:00 @ git:ccab071+local_

Design record (2026-09-20). Invocation.swift is written and committed by the main session with the four types: Invocation(context:questions:), ContextSource(.text/.file), Question(instructions:options:), Option(id:description:). All are public, Sendable, Equatable with memberwise public inits. The parser issue does not change that file. Decisions beyond the issue text: (1) ParseResult is 'enum ParseResult: Equatable { case help; case run(Invocation) }'. (2) UsageError is 'struct UsageError: Error, Equatable { let message: String }'; messages are bare (no 'Error: ' prefix, wip/ayd adds it when printing) and name the question by number and text, e.g. 'question 2 ("How urgent is this ticket?") has no --option'. (3) '--context @' with nothing after the @ is a usage error. (4) An empty question token ("") is a usage error. (5) '--option' with an empty id ('--option ""' or '--option =desc') is a usage error. (6) Only --context and --option take values; both accept '--flag value' and '--flag=value', split at the first '='. (7) '--help' and '-h' win wherever they appear, even after a usage error would have been raised by an earlier token? No: the walk stops at the first error it meets, except that --help anywhere returns .help; so the parser scans for --help/-h first, then walks. Implemented by a worker in a scratch worktree, then copied back.

---

_📝 Noted on 2026-09-20 18:32:43-04:00 @ git:e31b7ea+local_

Landed from the worker's worktree: UsageError.swift, CommandLineParser.swift, CommandLineParserTests.swift (23 tests). Worker judgement calls, accepted: '--context=' with nothing after the = gives .text("") (only the two-token form errors on a missing value); final checks run one pass per question (no --option first, then duplicates); the unknown-flag test also covers a lone '-'. Main-tree build is clean under -warnings-as-errors and the suite passes.
