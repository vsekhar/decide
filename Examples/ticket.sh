#!/bin/sh

set -eux
cd "$(dirname "$0")"

./decide --context @ticket.txt \
         "Which team handles this ticket?" \
         --option shipping \
         --option billing \
         --option returns
echo "exit=$?"
