# decide

Make decisions from the command line.

A decision model does not write text. It reads a context, answers a fixed
set of questions, and returns a probability for each possible answer.
`decide` puts that on the command line. One question about one file is a
shell one-liner. Many questions about a stream of events is the same
command with one more flag, and each event costs one request no matter how
many questions you ask.

```sh
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns

returns
```

```sh
# Show me your work (JSON)
$ decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
         --json

{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"returns":0.91,"shipping":0.06,"billing":0.03}}
```

```sh
# How bad? (explain choices for better decisions)
$ decide --context @ticket.txt \
         "How urgent is this ticket?" \
         --level not_urgent="Customer feedback or feature request" \
         --level somewhat_urgent="Customer problem, but customer not blocked" \
         --level urgent="Customer blocked"
somewhat_urgent
```

```sh
# Apply policy (multiple named contexts, custom threshold, custom answers, explanation)
$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         "Should we issue a refund?" \
         --min_confidence=0.7 \
         --yes "Hell yeah"="Allowed by the policy and desired by the customer" \
         --no "Forget it"

Hell yeah
```

```sh
# Control a script (--exit terminates with 0 for yes and 1 for no because bash...)
if decide --context="$body" "Is this message spam?" \
          --min_confidence=0.7 \
          --exit; then
  mv "$file" spam/
fi
```

```sh
# Batch questions (reads context once, much faster and cheaper)
$ decide --context @ticket.txt \
     "Which team handles this ticket?" --option shipping --option billing --option returns \
     "How urgent is this ticket?" --level not_urgent --level somewhat_urgent --level urgent \
     "Should we issue a refund?" --min_confidence 0.7 --yes Yes --no No
returns
somewhat_urgent
Yes
```

```sh
# Questions from a file
$ cat triage.decide
"Which team handles this ticket" --option shipping --option billing --option returns
"How urgent is this ticket" --level not_urgent --level somewhat_urgent --level urgent
"Should we issue a refund" --min_confidence 0.7 --yes Yes --no No

$ decide --context @ticket.txt --questions @triage.decide
returns
somewhat_urgent
Yes
```

```sh
# Stream named JSON context, decide for each line on STDIN
cat events.jsonl | decide --context policy=@policy.txt \
                          --context-json event=- \
                          --each \
                          --questions @triage.decide \
                          --json > triage_decisions.jsonl
```

```sh
# Handle non-decision errors (loss of network, etc.) with --fallback
$ sudo ip link set eth0 down
$ decide --context "$body" \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
         --min_confidence 0.7 \
         --fallback human

stderr>  Error: cannot reach decision model server
human
```

```sh
# Define safe path for a script
if decide --context "$body" "Is this message spam?" --exit --fallback false; then
  mv "$file" spam/     # never reached on an error
fi
```

```sh
# Advanced: JSON questionnaire (names, richer descriptions, structured instructions)
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
      "min_confidence": 0.7
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

```sh
# Named questions give keyed JSON output
$ decide --context ticket=@ticket.txt \
         --context refund_policy=@refund_policy.txt \
         --questions @triage.json --json
{"team":{"kind":"choice","answer":"returns","confidence":0.91,"probabilities":{"returns":0.91,"shipping":0.06,"billing":0.03}},
 "urgency":{"kind":"rating","answer":"somewhat_urgent","score":1.2,"confidence":0.78,"probabilities":{"not_urgent":0.15,"somewhat_urgent":0.55,"urgent":0.30}},
 "refund":{"kind":"verdict","answer":true,"probability":0.87}}
```

The JSON form adds what a one-line grammar cannot carry:

- **Names.** Each question gets a `name`, so JSON output is keyed instead of
  ordered, and `--annotate` knows where to put each answer in an event.
- **Richer options and levels.** Beside a `summary`, an option or level can
  say what it is `not_for`, give `examples`, and list `signals` to look for.
  A plain string still works where you need no more than an id.
- **Both sides of a yes or no question.** `yes` and `no` take the same
  shape as an option: a label, or an object with an `id` to print and a
  `summary` that tells the model what that side means.
- **Structured instructions.** `instructions` can be an object, such as a
  question plus a list of rules, instead of one line of text.
- **Per-question settings next to the question.** `min_confidence` lives
  with the question it governs.
- **Generated questionnaires.** A program can write the file, so an ingest
  pipeline can build its questions from a catalog or a database.

## Setup

```sh
# Read model and key from environment
$ export DECIDE_MODEL=jev-latest
$ export DECIDE_MODEL_API_KEY=abc123...
$ decide ...
```

```sh
# Specify model and/or key on command line (overrides environment)
$ decide --model=jev-latest --key=abc123... ...
```

## Exit codes
