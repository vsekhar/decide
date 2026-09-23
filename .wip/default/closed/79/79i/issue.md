---
priority: p2
type: feature
created: 2026-09-23T00:38:42-04:00
updated: 2026-09-23T03:12:09-04:00
---

# --model and --api-key without --set-config override the model and key for one run

# --model and --api-key without --set-config override the model and key for one run

## Objective

`decide --model openrouter:typesafe/jev-1.13 "Is Atlanta the capital of Georgia?"` runs that question against that model, whatever `DECIDE_MODEL` and every config file say. `--api-key <key>` does the same for the key. Flags win over the environment, which wins over the config files. Without either flag a run behaves exactly as today. With `--set-config` the two flags keep their current meaning (what to write), and `--project` still needs `--set-config`.

## Context

Requested by the user on 2026-09-23. Today the main grammar throws `--model needs --set-config` and `--api-key needs --set-config` (`CommandLineParser.swift`, the `setConfigFlag` check in `parse`), a placeholder wip/chc listed as out of scope: "the precedence rule here holds once they exist, because flags are applied last." wip/jq1 built `--set-config`, and its `parseSetConfig` pre-scan owns any line that holds `--set-config`, so this issue touches only the main grammar. wip/rvj built the config chain: `Decide.run` lays the merged files under `environment` with `ConfigFiles.environment(_:over:)` and then builds `ModelConfiguration(environment:)`. The flags are one more layer on top of that dictionary, laid last.

## Location

- `Sources/DecideCore/Invocation.swift`: two fields and a helper.
- `Sources/DecideCore/CommandLineParser.swift`: the main grammar takes the two flags; `setConfigFlag` shrinks to `--project`.
- `Sources/DecideCore/Decide.swift`: the override in `run`, after the config step; the usage text.
- `README.md`, "Install and Setup".
- `Tests/DecideCoreTests/CommandLineParserTests.swift`, `DecideRunTests.swift`, `DecideLiveTests.swift`; a small `InvocationTests.swift` is fine for the helper, or put it in `DecideRunTests`.

## Approach

**Invocation.** `public var model: String?` and `public var apiKey: String?`, doc comments "The model for this run from `--model`, or nil to use the environment and the config files" and the same for the key. The initializer gains `model: String? = nil, apiKey: String? = nil` after `quiet`, so every existing call site compiles unchanged. The type's doc comment gains: "and the model and key to use, when the line names them." A helper, `public func applied(to environment: [String: String]) -> [String: String]`: a copy of the environment with `DECIDE_MODEL` set to `model` when that is non-nil and `DECIDE_MODEL_API_KEY` set to `apiKey` when that is non-nil; every other variable passes through. Use `ModelConfiguration.modelVariable` and `.apiKeyVariable` for the names. Pure, so a unit test proves the precedence without a model.

**Parser.** In the main loop, before the `setConfigFlag` check, take `--model <v>` and `--model=<v>` through `flagValue`, once: a second one is `--model was given twice`; a value that is empty or only whitespace is `--model is empty` (reuse `setting(_:of:)`); the value is not trimmed. The same for `--api-key`. Either may appear anywhere on the line, before or after questions, like `--context`. `setConfigFlag` then matches only `--project`, so `--project` alone still throws `--project needs --set-config`. Lines holding `--set-config` are unchanged: the pre-scan runs first. The `parse` doc comment gains one sentence: "`--model` and `--api-key` set the model and key for this run, over the environment and every config file."

**Run.** In `Decide.run`, right after the `if let currentDirectory { ... }` config block and before `ModelConfiguration` is built: `environment = invocation.applied(to: environment)`. That is the whole precedence rule: files under environment, flags over both. The override applies whether or not a working directory was given. An injected test model still bypasses `ModelConfiguration`, as today.

**Usage text.** Replace the four `--set-config` lines with, in this order and the file's current column:

```
  --model <model>                The model for this run, provider:model. Wins over
                                 the environment and every config file.
  --api-key <key>                The API key for this run. Wins over the environment
                                 and every config file.
  --set-config                   Write --model and --api-key to the home config and exit.
  --project                      With --set-config, write ./.decide/config instead.
```

In the Environment paragraph, after "the environment wins over every file." add "--model and --api-key win over both."

**README**, "Install and Setup": the block becomes

```sh
$ brew install vsekhar/tap/decide
$ decide --set-config --model typesafe:jev-latest --api-key abc123...

# For one run, --model and --api-key on the command line win over every setting
$ decide --model openrouter:typesafe/jev-1.13 "Is Atlanta the capital of Georgia?"
```

## Tests

- Parser: `--model a:b Q` and `Q --model=a:b` give `Invocation(context: nil, questions: [...], quiet: false, model: "a:b", apiKey: nil)`; `--api-key k` both forms; both flags with `--context` and two questions; `--model` twice, `--api-key` twice, `--model=` empty and `--model " "` (the four messages); `--project` alone still `--project needs --set-config`; `--set-config --model a:b` still `.setConfig`; the existing test `setConfigFlagsNeedTheFlag` shrinks to `--project`.
- `applied(to:)`: model set replaces a set `DECIDE_MODEL`; key set replaces a set key; nil leaves each alone; unrelated variables pass through; both nil returns the environment unchanged.
- Run level, no injected model, hermetic: `["--model", "nosuch:x", "Q?"]` with `environment: ["DECIDE_MODEL": "typesafe:jev-latest"]` exits 10 with the unknown-provider message naming `nosuch`, proving the flag beat the environment; the same with a `ConfigTree` project file naming `typesafe:jev-latest`, an empty environment but `HOME`, and `currentDirectory: tree.sub`, proving the flag beat a file; `["--model", "jev-latest", "Q?"]` exits 10 with the not-provider:model message, proving the flag goes through the same check. A scripted-model run with `--model` and `--api-key` on the line still answers, proving the flags do not disturb a run.
- Live, one round trip: `["--api-key", "not-a-key", "Is Atlanta the capital of Georgia?"]` with the real environment (`DECIDE_MODEL` and the real key set) exits 10 with `Error: the model server rejected the API key.` and nothing on stdout. A scripted model cannot see the key reach the provider, so this earns its round trip (TESTING.md).

## Design Decisions

- Flags over environment over files: the request, and chc's rule. No flag can unset a value; `--model ""` is an error, as an empty file value is.
- The override is one pure function on `Invocation`, applied to the environment dictionary, so `ModelConfiguration` and the providers change nothing and the precedence is testable without a model.
- `--api-key` on the command line is not a trust-boundary case: the rule keeps a key out of a project file, and a flag lands in no file. It does land in shell history and `ps` output, as any flag does; the usage text need not say so.
- No `--model` default provider: the value is `provider:model`, as `DECIDE_MODEL` is.

## Related Issues

wip/chc (config files; listed these flags as out of scope), wip/jq1 (`--set-config`, whose pre-scan is untouched), wip/rvj (the config step in `Decide.run` this layers on).

## Acceptance Criteria

- [ ] `decide --model <provider:model> "<question>"` uses that model, and `--api-key <key>` that key, over `DECIDE_MODEL`, `DECIDE_MODEL_API_KEY`, and every config file.
- [ ] Each flag is taken once, refuses an empty or blank value, and works in both value forms anywhere on the line; `--project` without `--set-config` is still an error; `--set-config` lines are unchanged.
- [ ] `Invocation.applied(to:)` is unit-tested for the precedence; the run-level tests prove the flag beats the environment and a file with no network; the live test proves a flag key reaches the provider.
- [ ] `--help` and the README describe the flags and their precedence.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean; `swift test --skip DecideLive` passes; `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-23 02:58:22-04:00 @ git:1e11d31+local_

Design record (2026-09-23), the decisions the Approach left open. Implemented as written there, plus:
1. setConfigFlag(_:) is deleted, not shrunk: with --model and --api-key in the main grammar it would match one token, so the main loop checks `token == "--project"` inline and throws `--project needs --set-config`. Its doc comment goes with it.
2. The two flags sit in the main loop right after --context, through flagValue, each guarded by a `was given twice` check and passed through setting(_:of:) for the empty/blank error, so the messages are `--model was given twice`, `--model is empty`, and the same for --api-key. Values are not trimmed; ModelConfiguration trims the model when it reads it.
3. Invocation.applied(to:) needs no import: ModelConfiguration is in the same module. It copies the dictionary and assigns the two keys when set.
4. The Environment paragraph of the usage text is rewrapped to fit its column after the new sentence; the words are the issue's.
5. The applied(to:) tests live in a new Tests/DecideCoreTests/InvocationTests.swift, suite "Invocation". TESTING.md's list of suite names was already stale (ConfigFile and ConfigFiles were missing), so it is rewritten to list every suite, Invocation included.
6. The live test asserts the exact line `Error: the model server rejected the API key.` and exit 10. If the real provider maps a bad key to some other error, that is a finding to report, not an assertion to loosen.
7. wip/ndr landed first (Invocation.context is now Context?); the new init parameters go after quiet, both defaulted, so every call site compiles unchanged.

---

_📝 Noted on 2026-09-23 03:05:16-04:00 @ git:1e11d31+local_

Implementation (2026-09-23): a worker implemented the Approach and the design record as written; no open question came up. Beyond the record:
- setting(_:of:) now serves both grammars, so its doc's first words changed from "The value of a --set-config flag" to "The value of a --model or --api-key flag". Code unchanged.
- One parser test added beyond the list, setConfigModelAlone (`--set-config --model a:b` gives .setConfig with a nil key), because no existing test covered that exact line.
- The live test passed on the first run: the real provider answers a bad flag key with exit 10 and exactly `Error: the model server rejected the API key.`, with the real key still in the environment. So a flag key beats an environment key on the wire.
Checks: warnings-as-errors build clean; `swift test --skip DecideLive` 271 tests in 8 suites pass; the live suite 4 tests pass.

---

_📝 Noted on 2026-09-23 03:12:09-04:00 @ git:1e11d31+local_

Summary (2026-09-23): done. --model and --api-key in the main grammar set Invocation.model and .apiKey; Invocation.applied(to:) lays them over the environment after the config-file merge in Decide.run, so flags beat the environment, which beats the files. --set-config lines are untouched; setConfigFlag is gone and --project alone still errors. Usage, README Install block, and TESTING.md suite list updated.
Verifier: all five acceptance criteria hold, no blockers. Acted on two notes: the Invocation test that checked two subscripts now compares whole dictionaries and a both-flags case was added; the two precedence run tests now put `other:model` (an unknown provider) in the environment and the project file instead of typesafe:jev-latest, so the failure path builds no real model either, and they assert the message names nosuch and not other. A mutant that drops the override line fails both tests with "other" in the message and no network. Left as a note: the new --set-config usage line is 89 printed columns, two past the old widest; it is the issue's verbatim text.
Final: warnings-as-errors build clean; `swift test` with .env sourced, 276 tests in 9 suites passed, live included.
