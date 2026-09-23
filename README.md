# decide

[![CI](https://github.com/vsekhar/decide/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/vsekhar/decide/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/vsekhar/decide/branch/main/graph/badge.svg)](https://codecov.io/gh/vsekhar/decide)

Make decisions from the command line.

## Install and Setup

```sh
$ brew install vsekhar/tap/decide
$ decide --set-config --model typesafe:jev-latest --api-key abc123...
```

## Usage

```sh
# Yes/no decision (default)
$ decide "Is Atlanta the capital of Georgia?"
yes

# Choose from among options
$ decide "What kind of weather is typical in Florida?" \
    --option rainy \
    --option sunny \
    --option snowy
sunny

# Provide context
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns
returns

# Choose a level on a scale specified "least" to "most"
$ decide --context @ticket.txt \
         "How urgent is this ticket?" \
         --level not_urgent \
         --level somewhat_urgent \
         --level urgent
not_urgent

# Improve decisions by explaining options to the model
$ decide --context @ticket.txt \
         "How urgent is this ticket?" \
         --level not_urgent="Customer feedback or feature request" \
         --level somewhat_urgent="Customer problem, but customer not blocked" \
         --level urgent="Customer blocked"
somewhat_urgent

# Improve performance and cost by asking multiple questions at once against the same context
$ decide --context @ticket.txt \
     "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
     "How urgent is this ticket?" \
         --level not_urgent \
         --level somewhat_urgent \
         --level urgent \
     "Should we issue a refund?"
returns
somewhat_urgent
yes

# Compose context from multiple sources, refer by name in questions and options
$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         "Should we issue a refund?" \
         --yes yes="Allowed by refund_policy and requested in ticket"
no
```

## Advanced usage

### Question files

Question files can be stored and version controlled.

```sh
# Text question files mimic the command line
$ cat triage.txt
"Which team handles this ticket"
    --option shipping
    --option billing
    --option returns

"How urgent is this ticket"
    --level not_urgent
    --level somewhat_urgent
    --level urgent

"Should we issue a refund"

$ decide --context @ticket.txt --questions @triage.txt
returns
somewhat_urgent
yes
```

```sh
# JSON question files can use names, richer descriptions and structured instructions.
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

# Parse named questions using --json (and jq)
$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         --questions @triage.json \
         --json
{"team":{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"returns":0.91,"shipping":0.06,"billing":0.03}},
 "urgency":{"kind":"rating","answer":"somewhat_urgent","score":1.2,"confidence":0.78,"probabilities":{"not_urgent":0.15,"somewhat_urgent":0.55,"urgent":0.30}},
 "refund":{"kind":"verdict","answer":true,"probability":0.87}}
```

### Scripting

```sh
# Get confidence and breakdown of probabilities as JSON (parse with jq)
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
         --json
{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"returns":0.91,"shipping":0.06,"billing":0.03}}

# Branch in a script via exit codes (-q suppresses printed output)
if decide --context="$body" "Is this message spam?" -q; then
  mv "$file" spam/
fi

# Customize output strings for yes/no
$ decide --context @ticket.txt \
         "Should we issue a refund?" \
         --yes "Hell yeah" \
         --no "Forget it"
Hell yeah

# Branch with custom output strings
if answer=$(decide --context="$body" "Is this message spam?" --yes spam --no ham); then
  mv "$file" "$answer/"
fi
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

## Errors

```sh
# Handle non-decision errors (loss of network, etc.) using `--fallback`
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

# Define safe path for a script
if decide --context "$body" "Is this message spam?" -q --fallback false; then
  mv "$file" spam/     # never reached on an error
fi
```

## Development

To build the tool or run its tests, see DEVELOPMENT.md and TESTING.md.

## Appendix

### Exit codes

For a choice, a rating, or a batch, decisions are printed to stdout and the exit code reports errors:

| Code | Decision |
|---|---|
| 0 | Decided: see stdout
| 1 | Not used
| 2 | Unsure: confidence below --min-confidence, no --fallback
| 3-9 | Reserved for decision-like states
| 10 | Not run: setup or input error (bad usage, model or key missing, unreadable file)
| 11 | Not decided: remote error (network, timeout, rate limit, model refused)

When the run has one yes/no question, the exit code carries the answer as well:

| Code | Decision |
|---|---|
| 0 | Decided: Yes
| 1 | Decided: No
| 2 | Unsure: confidence below --min-confidence, no --fallback
| 3-9 | Reserved for decision-like states
| 10 | Not run: setup or input error (bad usage, model or key missing, unreadable file)
| 11 | Not decided: remote error (network, timeout, rate limit, model refused)

Only 0 and 1 carry an answer. A script that branches on the exit code should put the action on the yes side,
or switch on `$?`.

`--fallback` turns an unsure answer (exit code 2) and a remote error (exit code 11) into decisions (exit code 0) and prints
the fallback value. With one yes/no question it returns the code of the fallback's side, or the fallback exit code.

In a stream, 10 stops the run at once. 2 and 11 are per event: the event
gets an error line or its fallback, the stream goes on, and the final code
is the highest code any event produced.
