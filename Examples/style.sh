#!/bin/sh

set -eux
cd "$(dirname "$0")"

./decide --context @loremipsum.txt \
         "What kind of text is this?" \
         --option filler="Filler text like lorem ipsum" \
         --option shakespeare="A work of Shakespeare or something in that style" \
         --option technical="A technical manual or specification" \
         --option casual="Casual or conversational prose"
echo "exit=$?"

./decide --context @hamlet.txt \
         \
         "What kind of text is this?" \
         --option filler="Filler text like lorem ipsum" \
         --option shakespeare="A work of Shakespeare or something in that style" \
         --option technical="A technical manual or specification" \
         --option casual="Casual or conversational prose" \
         \
         "At what school level would an English student study a passage like this?" \
         --option "Preschool"="Daycare through kindergarten" \
         --option "Elementary school"="Grades 1-6" \
         --option "High school"="rades 7-12" \
         --option "Post-secondary"="Undergrad, graduate, PhD"
echo "exit=$?"
