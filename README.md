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

# Compose context from multiple sources, refer by name in questions and options
$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         "Should we issue a refund?" \
         --yes yes="Allowed by refund_policy and requested in ticket"
no

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

# Name questions; a named question prints as name=answer
$ decide --context @ticket.txt \
     "Which team handles this ticket?"
        --name team \
        --option shipping \
        --option billing \
        --option returns \
     "Should we issue a refund?" \
         --name refund
team=returns
refund=yes
```

## Advanced usage

### Question files

Questions and their details can be read from files. This is useful for placing questions under version control.

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

Multiple question files can be specified, and questions on the command line and in files can be mixed. Questions from a file are inserted where the corresponding `--questions` flag appears on the command line.

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

team=returns
urgency=somewhat_urgent
refund=Yes
```

### Statistics: confidence and probabilities

```sh
# Request stats (confidence, probability) for a question with --stats
# Request full distribution (probabilities of all answers) for question with --distribution
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
             --name team \
             --option shipping \
             --option billing \
             --option returns \
             --distribution \
         "How urgent is this ticket?" \
             --level not_urgent \
             --level somewhat_urgent \
             --level urgent \
             --stats \
         "Should we issue a refund?" \
             --name refund
team=returns	confidence:0.910 probability:0.910	shipping:0.060	billing:0.030	returns:0.910
somewhat_urgent	confidence:0.780 probability:0.550 score:1.150
refund=yes

# Fields are tab-separated; values inside the stats field are space-separated
$ decide ... --stats | cut -f2 | cut -d' ' -f1 | cut -d: -f2                             # confidence
$ decide ... --distribution | cut -f3- | tr '\t' '\n' | grep '^billing:' | cut -d: -f2   # p('billing')
```

The chosen answer is always the answer with the highest probability and
`--stats` prints that value in the `probability` field.

The `confidence` value measures how sure the model is that it can answer the
question with the given options. This is usually the value you want to check:
low confidence means you should be cautious in acting on the model's decision.

Compare the two responses to identical questions with different options:

```sh
$ % decide "What is the capital of Georgia?" \
         --option Atlanta \
         --option Chicago \
         --distribution
Atlanta confidence:1.000 probability:1.000      Atlanta:1.000   Chicago:0.000

$ decide "What is the capital of Georgia?" \
         --option Atlanta \
         --option Tbilisi \
         --distribution
Tbilisi confidence:0.520 probability:0.760      Atlanta:0.240   Tbilisi:0.760
```

Notice that confidence is a function of the question as well as the given
options. When the options consist of only US cities, "Georgia" is resolved
to the US state and the model can answer confidently. When the options include
Tbilisi, the model is no longer confident it can correctly answer the
(ambiguous) question with the given options.

### Scripting

```sh
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

### JSON output

Full parseable details of a decision can be obtained via JSON output:

```sh
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
         --json
{"q1":{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}}}

$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         --questions @triage.json \
         --json
{"team":{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}},
 "urgency":{"kind":"rating","answer":"somewhat_urgent","score":1.15,"confidence":0.78,"probabilities":{"not_urgent":0.15,"somewhat_urgent":0.55,"urgent":0.3}},
 "refund":{"kind":"verdict","answer":"Yes","verdict":true,"confidence":0.74,"probabilities":{"Yes":0.87,"No":0.13}}}
```

JSON is output on one line (JSONL-style). The example above is wrapped for readability.

### Command line configuration

```sh
# Model and API key can be specified (or overridden) on the command line for zero-config usage
$ decide --model openrouter:typesafe/jev-1.13 \
         --api-key abc123... \
         "Is Atlanta the capital of Georgia?"
yes
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
