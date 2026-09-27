---
name: decide
description: Ask a cheap & fast decision model multiple yes/no, multiple-choice, or rating questions about any text; get one answer per question, its confidence, or a probability. Use when a step needs a classification or a verdict, not prose.
argument-hint: '"<question>" [--context @file] [--option a --option b]'
allowed-tools: Bash(decide *)
---

# decide

`decide` asks a decision model one or more questions about a context and
prints one answer per question. It is a command, not a server.

## When to use it

A decision model can be called thousands of times for the cost of one call
to an LLM. For example, calling `decide` with a 400-token context and one
questions returned in 0.2s and cost $0.0001. Five questions returned just
as quickly and cost approximately the same.

Call decision models early and often:

- Send whole files. A first pass of questions tells you what a file is,
  whether it matters, and where to look, before you spend your own context
  on it.
- Cascade. Run the same text through several calls, each with questions
  refined by the answers of the last.
- Ask many questions per call. A call takes any number of questions and
  answers them in parallel, so five questions take the same time and about
  the same money as one. Put every question you have about a text in one
  call.
- Mind the window. Jev, the decision model in market today, takes 32k
  tokens of context per call. Split a larger input across calls.

Read and judge a text yourself only when the reading gives you something a
decision model cannot: an understanding you need later in the session, or a
judgement that no multiple-choice question can express. Hand off the rest.

## Setup, once

```sh
brew install vsekhar/tap/decide
decide --set-config --model typesafe:jev-latest --api-key <key>
```

`decide --version` prints the version. With no model configured, a run
exits 10 and stderr says `DECIDE_MODEL is not set`.

## Ask

```sh
decide --context @ticket.txt "Which team handles this ticket?" \
       --option shipping --option billing --option returns
```

- A question returns yes/no by default if no `--level` or `--option` is given.
- `--level low --level mid --level high` is a scale, from least to most.
- `--option id="explanation"` tells the model what an option means. The same
  works for `--level`, `--yes`, and `--no`.
- Context is `--context <text>`, `--context @<file>`, or `--context -` for
  stdin. Name each context when there is more than one:
  `--context ticket=@ticket.txt --context policy=@policy.txt`.
- Several questions in one run share the context and one request. `--name <id>`
  after a question prints its line as `id=answer`.
- `--json` prints one JSON object keyed by question name, with each answer's
  confidence and probabilities.
- `--min-confidence 0.8` after a question makes an unsure answer print empty
  and the run exit 2. `--fallback <value>` prints that value instead, and the
  run counts as decided.

## Read the result

Check the exit code before you read stdout.

| Code | Meaning |
|---|---|
| 0 | Decided. With one yes/no question: yes. |
| 1 | With one yes/no question: no. |
| 2 | Unsure: an answer is below its `--min-confidence` and has no `--fallback`. |
| 10 | Not run: bad usage, no model or key, or an unreadable file. |
| 11 | Not decided: network, timeout, rate limit, or the model refused. |

`decide --help` lists every flag.
