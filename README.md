# decide

[![CI](https://github.com/vsekhar/decide/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/vsekhar/decide/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vsekhar/decide/branch/main/graph/badge.svg)](https://codecov.io/gh/vsekhar/decide)

Make decisions from the command line.

A decision model does not write text. It reads a context, answers a fixed
set of questions, and returns a probability for each possible answer.
`decide` puts that on the command line. One question about one file is a
shell one-liner. Many questions about a stream of events is the same
command with one more flag, and each event costs one request no matter how
many questions you ask.

### Classification

Choose from among discrete choices:

```sh
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns

returns
```

Full details for all decisions are available as parsable JSON:

```sh
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
         --json

{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"returns":0.91,"shipping":0.06,"billing":0.03}}
```

### Levelling

Choose a level on a linear scale, where each level is "more of something" than the last:

```sh
$ decide --context @ticket.txt \
         "How urgent is this ticket?" \
         --level not_urgent \
         --level somewhat_urgent \
         --level urgent
not_urgent
```

Levels and options aren't just labels, they can include descriptions provided to the model to get better decisions:

```sh
$ decide --context @ticket.txt \
         "How urgent is this ticket?" \
         --level not_urgent="Customer feedback or feature request" \
         --level somewhat_urgent="Customer problem, but customer not blocked" \
         --level urgent="Customer blocked"
somewhat_urgent
```

### Yes or no

Make a yes or no decision, with a custom confidence threshold and custom output values:

```sh
$ decide --context @ticket.txt \
         "Should we issue a refund?" \
         --min-confidence=0.7 \ # anything less is a No
         --yes "Hell yeah" \
         --no "Forget it"

Hell yeah
```

### Composite context

Compose multiple named context sources and refer to them in the question and option descriptions:

```sh
$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         "Should we issue a refund?" \
         --min-confidence=0.7 \
         --yes "Hell yeah"="Allowed by refund_policy and requested in ticket" \
         --no "Forget it"

Forget it
```

Use exit codes to control a script using yes or no decisions:

```sh
if decide --context="$body" \
          "Is this message spam?" \
          --min-confidence=0.7 \
          --exit; then
  mv "$file" spam/
fi
```

### Batch questions

Improve performance and decrease costs by batching questions for a given context:

```sh
$ decide --context @ticket.txt \
     "Which team handles this ticket?" --option shipping --option billing --option returns \
     "How urgent is this ticket?" --level not_urgent --level somewhat_urgent --level urgent \
     "Should we issue a refund?" --min-confidence 0.7 --yes Yes --no No
returns
somewhat_urgent
Yes
```

Read multiple questions from a file:

```sh
# Questions from a file
$ cat triage.decide
"Which team handles this ticket" --option shipping --option billing --option returns
"How urgent is this ticket" --level not_urgent --level somewhat_urgent --level urgent
"Should we issue a refund" --min-confidence 0.7 --yes Yes --no No

$ decide --context @ticket.txt --questions @triage.decide
returns
somewhat_urgent
Yes
```

### Streaming

```sh
# Stream named JSON context, decide for each line on STDIN
cat events.jsonl | decide --context policy=@policy.txt \
                          --context-json event=- \
                          --each \
                          --questions @triage.decide \
                          --json > triage_decisions.jsonl
```

### Errors

Handle non-decision errors (loss of network, etc.) using `--fallback`:

```sh
$ sudo ip link set eth0 down
$ decide --context "$body" \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
         --min-confidence 0.7 \
         --fallback human

stderr>  Error: cannot reach decision model server
human
```

Define safe paths for scripts:

```sh
# Define safe path for a script
if decide --context "$body" "Is this message spam?" --exit --fallback false; then
  mv "$file" spam/     # never reached on an error
fi
```

### Advanced Questionnaires

Advanced questionnaires can use names, richer descriptions and structured instructions.

```sh
$ cat triage.json
{
  "questions": [
    {
      "name": "team",
      "instructions": "Which team handles this ticket?",
      "options": [
        {
          "id": "shipping",
          "summary": "Delivery issues",
          "examples": ["Package is late", "Tracking says delivered but nothing arrived"],
          "signals": ["Names a carrier or a tracking number"]
        },
        {
          "id": "billing",
          "summary": "Payment problems",
          "not_for": "Money back for an item the customer returned; that is returns",
          "examples": ["Charged twice", "Card declined at checkout"]
        },
        {
          "id": "returns",
          "summary": "Exchanges and refunds",
          "not_for": "Damage in transit; that is shipping",
          "examples": ["Wrong size", "Wants money back for a returned item"]
        }
      ]
    },
    {
      "name": "urgency",
      "instructions": "How urgent is this ticket?",
      "levels": [
        {"id": "not_urgent",      "summary": "Customer feedback or feature request"},
        {"id": "somewhat_urgent", "summary": "Customer problem, but customer not blocked"},
        {"id": "urgent",          "summary": "Customer blocked",
                                  "signals": ["cannot", "stuck", "deadline", "today"]}
      ]
    },
    {
      "name": "refund",
      "instructions": {
        "question": "Should we issue a refund?",
        "rules": [
          "Apply `refund_policy` to the `ticket`.",
          "When the policy is silent, answer no."
        ]
      },
      "yes": {"id": "Yes", "summary": "The policy allows a refund for this case"},
      "no":  {"id": "No",  "summary": "The policy forbids it, or the customer does not ask for money back"},
      "min-confidence": 0.7
    }
  ]
}

$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         --questions @triage.json

returns
somewhat_urgent
Yes
```

Named questions can be parsed out of batched or complex questionnaires with JSON output:

```sh
$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         --questions @triage.json --json
{"team":{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"returns":0.91,"shipping":0.06,"billing":0.03}},
 "urgency":{"kind":"rating","answer":"somewhat_urgent","score":1.2,"confidence":0.78,"probabilities":{"not_urgent":0.15,"somewhat_urgent":0.55,"urgent":0.30}},
 "refund":{"kind":"verdict","answer":true,"probability":0.87}}
```

## Setup

The model and API key are read from the environment. The model is
`provider:model`. The provider is `typesafe` or `openrouter`, and the model
part goes to the provider as is:

```sh
$ export DECIDE_MODEL=typesafe:jev-latest    # or openrouter:typesafe/jev-1.13
$ export DECIDE_MODEL_API_KEY=abc123...
$ decide ...
```

Both can be specified or overridden on the command line:

```sh
$ decide --model=typesafe:jev-latest --model-api-key=abc123... ...
```

## Development

To build the tool or run its tests, see DEVELOPMENT.md and TESTING.md.

## Appendix

### Exit codes and errors

Decisions are printed to stdout and the exit code reports errors:

| Code | Decision |
|---|---|
| 0 | Decided: see stdout
| 1 | Not used
| 2 | Not decided: setup or input error (bad usage, model or key missing)
| 3 | Not decided: runtime error (network, timeout, rate limit)

When the `--exit` flag is used for scripting, the error code carries the decision and stdout is not used:

| Code | Decision |
|---|---|
| 0 | Decided: Yes
| 1 | Decided: No
| 2 | Not decided: setup or input error (bad usage, model or key missing)
| 3 | Not decided: runtime error (network, timeout, rate limit)

Only 0 and 1 carry an answer. A script that branches on `--exit` should put the action on the yes side,
or switch on `$?`.

`--fallback` turns runtime errors (exit code 3) into decisions (exit code 0) and prints the fallback value. With `--exit` it
returns the code of the fallback's side, or the fallback exit code.

In a stream, 2 stops the run at once. 3 is per event: the failed
event gets an error line or its fallback, the stream goes on, and the final
code is 4 if any event failed without a fallback.
