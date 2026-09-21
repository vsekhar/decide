#!/bin/sh

set -eux
cd "$(dirname "$0")"

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
         --yes Yes \
         --no No
echo "exit=$?"
