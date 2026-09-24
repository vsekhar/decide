---
priority: p2
type: feature
created: 2026-09-23T01:25:20-04:00
updated: 2026-09-24T01:14:56-04:00
---

# JSON question files

# JSON question files

## Summary

`decide --questions @triage.json` reads questions from a JSON file in the README's schema: named questions, instructions with rules, and options, levels, and yes/no sides that carry a summary, `not_for`, `examples`, and `signals`. `--questions` tells the two file kinds apart by content, so one flag serves both and the README's examples run as written. The questions land in the run exactly as text-file questions do: in the flag's place, mixed with any others.

## User Story

A team writes its triage questions once, with examples and rules that make the model's answers better, keeps the file under version control, and runs it with the same command as a text file. A reviewer sees the question's name in the output once `--json` output exists.

## Design Decisions

Decided with the user on 2026-09-23, after weighing a dedicated `--questions-json` flag, extension detection, and content detection.

- **One `--questions` flag, decided by content.** The first non-blank character `{` means JSON; anything else is the text grammar. A text question file cannot start with `{`: its first token is a question, quoted in practice, so the discriminator is reliable. Extension detection fails for stdin, inline text, process substitution, and the README's own `triage.decide`; a dedicated flag would still need the sniff to catch `--questions @triage.json` and would add a flag for no gain. A strict `--questions-json` can be added later without changing anything built here.
- **`--context-json` is a separate, explicit flag**, not built here. A context is arbitrary text, and text that begins with `{` must stay text, so sniffing is unsafe for contexts. This asymmetry is the whole reason questions may sniff and contexts may not.
- **Strict schema.** Unknown keys, a wrong type, a missing `id`, a question that mixes kinds, and a bad name are errors that name the file and the JSON path. A silently ignored typo in `examples` would degrade answers with no sign.
- **A name is the question's id.** The library's spec id is the name, so the model sees it, messages use it, and a later `--json` output keys by it. Unnamed questions keep `q<N>`, where N is the position in the run. Names are identifiers, the same rule as context names (wip/ndr), and unique across a run.
- **Structure passes through untouched.** Rules become the library's object instructions `{"question", "rules"}`; criterion fields become the library's `Criterion`. The library's preflight refuses either for a provider that cannot take it, which decide already reports as exit 10, so no capability logic lives in decide.
- **A top-level array is refused**, with a message saying the file is an object with a `questions` array, so the one shape in the README is the one shape that works.
- **The expansion returns items.** wip/qc4 was amended so `--questions` yields `.token` or `.questions` items and the parser splices finished questions in place; the JSON path adds the second case without a second grammar.

## Out of Scope

- `--json` output (the README's Scripting and question-file examples). Names are carried now so it can key by them later.
- `--questions-json`, `--context-json`, `--questions -` for stdin.
- Any schema key the README does not show.

## Testing Strategy

The model child is proved by recording tests on `makeQuestionnaire`. The decoder is pure and tested on text, with the README's file as the whole-value fixture and one test per rule. The splice is tested with an in-memory reader and at run level with temp files and a scripted model whose records are keyed by name. One live test runs the README's JSON file against the real model, because only a live call shows that structured instructions and criteria cross the wire through decide's mapping and that the provider accepts them.

## Children

| ID | Title | Blocked on |
|---|---|---|
| g3q | Questions carry a name, rules, and rich criteria, and the questionnaire sends them | - |
| hah | Decode a JSON question file into questions, strictly, with a path in every message | g3q |
| rqr | --questions reads a JSON file when it starts with {, and splices its questions in place | hah, wip/qc4 |

Start with the model child; it touches `Runner.decide`, as wip/ndr does, so land one of the two before starting the other.

---

_📝 Noted on 2026-09-24 01:14:56-04:00 @ git:5d10b3a+local_

Summary (2026-09-24): all three children landed: wip/g3q (names, rules, criteria on the wire), wip/hah (cb3a694, the strict decoder), wip/rqr (this commit, the sniff and the splice). The README's triage.json runs end to end, offline against a scripted model and live against the real one, and prints its three named answers. The scope of the title is met.
