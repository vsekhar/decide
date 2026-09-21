#!/bin/sh
# The README's batch example, with the Leveling section's described levels:
# three questions of three kinds about one ticket, in one request. The refund
# question sets a confidence bar, so the run exits 2 with nothing on stdout
# when the model is unsure there. The script exits with decide's code and
# reports it on stderr, so stdout holds only the answers.

set -ux
cd "$(dirname "$0")" || exit 1

./decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns \
         "How urgent is this ticket?" \
         --level not_urgent="Customer feedback or feature request" \
         --level somewhat_urgent="Customer problem, but customer not blocked" \
         --level urgent="Customer blocked" \
         "Should we issue a refund?" \
         --min-confidence 0.7 \
         --yes Yes \
         --no No
status=$?
echo "exit=$status" >&2
exit "$status"
