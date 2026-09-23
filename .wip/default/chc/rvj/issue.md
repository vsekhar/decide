---
priority: p2
type: task
created: 2026-09-21T20:15:50-04:00
updated: 2026-09-22T22:28:02-04:00
blocked-on:
  - mia
may-unblock:
  - jq1
---

# Read .decide/config from the working directory upward and the home directory, and apply it under the environment

## Objective

`decide` reads `.decide/config` from the working directory, each parent up to the root or the home directory, and the home directory's two places, merges them with the nearest file winning per key, and lays the result under the environment before the model is configured. Any problem in any file stops the run with exit 10 and a message that names the file and line.

## Context

Part of wip/chc; its Design Decisions section is the record for the places, the stop rule, the merge, the precedence, and the trust boundary. Blocked on wip/mia, the parser. The keys are the environment variable names, so applying config is one step: for each key the environment does not set (unset, or set but blank after trimming, as `ModelConfiguration` already treats blank), take the nearest file's value. `DECIDE_MODEL_API_KEY` is read only from the home files; in a project file it is an error that names the file and line.

Isolation matters: a test that lets the walk run from the package directory would read the developer's real files. `Decide.run` therefore reads config only when given a working directory, the path computation is pure, and the loader takes an injected reader.

## Design

New file `Sources/DecideCore/ConfigFiles.swift`:

- `public enum ConfigFiles`.
- `public static func paths(currentDirectory: String, environment: [String: String]) -> (project: [String], home: [String])`. Pure. `currentDirectory` is an absolute, standardized path. Project: for each directory from `currentDirectory` upward, stop before the home directory when `HOME` is set and non-blank, and stop after the root; each yields `<dir>/.decide/config`. Home, when `HOME` is set and non-blank: `<xdg>/decide/config` where `xdg` is `XDG_CONFIG_HOME` if set and non-blank, else `<HOME>/.config`; then `<HOME>/.decide/config`. Compare directories as standardized paths so `HOME` with a trailing slash still stops the walk. No double slashes at the root.
- `public static func load(paths: (project: [String], home: [String]), read: (String) throws -> String?) throws(ConfigError) -> [String: String]`. `read` returns `nil` when there is no file at the path; throws when the path exists but cannot be read, which becomes `ConfigError(path, 0, "cannot read the file")`; a reader that finds bytes that are not UTF-8 reports `ConfigError(path, 0, "is not valid UTF-8")` (the real reader does the decoding and returns nil or throws a typed reason; design the closure's error so the loader can tell the two apart, for example `read: (String) throws(ConfigReadError) -> String?` with cases `unreadable` and `notUTF8`). For each path, project then home, in order: skip nil; parse with `ConfigFile.parse`; for a project path, an entry with key `DECIDE_MODEL_API_KEY` is `ConfigError(path, entry.line, "DECIDE_MODEL_API_KEY is allowed only in the home config, not in a project's")`; for each entry, set the key only if no nearer file set it.
- `public static func environment(_ environment: [String: String], over config: [String: String]) -> [String: String]`. Start from the environment; for each config key, when the environment's value is missing or blank after trimming, set it from config. Unrelated variables pass through untouched.
- A real reader in `Decide.swift` (private): `FileManager` existence check (a directory at the path counts as unreadable), `Data(contentsOf:)`, `String(data:encoding: .utf8)` nil means not UTF-8. This avoids the platform difference in `String(contentsOfFile:)` that TESTING.md notes.
- `Decide.run` gains `currentDirectory: String? = nil` after `environment`. When nil, no config is read; every existing test stays as it is. The executable passes `FileManager.default.currentDirectoryPath`. After argument parsing and before `ModelConfiguration`: compute paths, load with the real reader, catch `ConfigError` (print its message, return 10), and use `ConfigFiles.environment(environment, over: config)` as the environment for the rest of the run. Config is read even when a test injects a model, so run tests can prove the error paths.
- `Decide.usage`, Environment section gains after the two variables:
  ```
  Config files: .decide/config in the working directory and its parents,
  then ~/.config/decide/config and ~/.decide/config. Lines of
  KEY = "value" with the same two keys. The nearest file wins, and the
  environment wins over every file.
  ```
- `README.md`, Setup: a "Configuration files" subsection after the environment example: the format with a two-line example (a comment and a `DECIDE_MODEL` line), the places and the stop rule in two sentences, the merge and precedence in two sentences, the trust rule (the key only in the home file), and the shell-profile consequence. Leave the `--model` sentence alone; it is unfiled.
- `TESTING.md`: a short paragraph under the suite description: config tests read no real files; the loader's tests use an in-memory reader and the run tests a temp tree with `HOME` inside it.

## Location

- `Sources/DecideCore/ConfigFiles.swift` (new), `Sources/DecideCore/Decide.swift`, `Sources/decide/DecideCommand.swift`.
- `README.md` Setup, `TESTING.md`.
- `Tests/DecideCoreTests/ConfigFilesTests.swift` (new), `DecideRunTests.swift`.

## Tests

- `paths`: a working directory three levels under `HOME` yields three project paths, nearest first, and stops before `HOME`; the working directory equal to `HOME` yields none; a working directory outside `HOME` (`/srv/app/x`) walks to `/` and includes `/.decide/config` last; `HOME` unset or blank yields no home paths and a walk to the root; `XDG_CONFIG_HOME` set gives `<xdg>/decide/config` first; blank falls back to `<HOME>/.config`; `HOME` with a trailing slash still stops the walk; the second home path is `<HOME>/.decide/config`.
- `load` with an in-memory reader: nearest wins per key; a key only in the farthest file is used; a home key under a project key; nil paths skipped; `unreadable` and `notUTF8` become line-0 errors naming the path; a parse error carries the file's path and line; `DECIDE_MODEL_API_KEY` in a project file throws with the path and its line; the same key in either home file is accepted; both home files merge in order.
- `environment(_:over:)`: env set wins; env blank falls through; env unset falls through; config keys absent from env are added; unrelated variables pass through; an empty config returns the environment unchanged.
- Run level, temp tree with `HOME` inside it and no injected model: a project `.decide/config` with `DECIDE_MODEL = "typesafe:jev-latest"` and no key anywhere exits 10 with the not-configured message that names `DECIDE_MODEL_API_KEY` (which proves the model came from the file and no network was reached); a malformed file exits 10 with `path:line` in stderr and nothing on stdout; `DECIDE_MODEL_API_KEY` in the project file exits 10 with that message; the same key in `HOME/.config/decide/config` plus a scripted model runs to exit 0; `environment: ["DECIDE_MODEL": "openrouter:x"]` over a project file naming typesafe reaches the OpenRouter not-configured message (env wins); `currentDirectory: nil` reads nothing even when files exist.
- By hand, once, with a key: in a temp project directory with a `.decide/config` naming the model, and the key in a temp `HOME`'s `.config/decide/config`, run the binary with `env -u DECIDE_MODEL -u DECIDE_MODEL_API_KEY -u TYPESAFE_API_KEY -u OPENROUTER_API_KEY HOME=<temp>` and get an answer and exit 0. One paid request.

## Related Issues

Parent wip/chc. Blocked on wip/mia. The writer child follows this one. wip/33b's TESTING.md notes the `String(contentsOfFile:)` platform gap this loader avoids by decoding bytes itself.

## Acceptance Criteria

- [ ] With no environment variables set, a `.decide/config` in the working directory or a parent supplies the model and the home config supplies the key; the nearest file wins per key.
- [ ] `DECIDE_MODEL` in the environment wins over every file, and a blank one does not.
- [ ] A malformed file, an unknown key, an unreadable file, or `DECIDE_MODEL_API_KEY` in a project file exits 10 with `path:line` in the message and nothing on stdout.
- [ ] No test reads a file outside a temp directory; the suite passes with and without real config files on the machine.
- [ ] `--help` and the README's Setup section describe the files, the lookup, and the precedence.
- [ ] `swift build --build-tests -Xswiftc -warnings-as-errors` is clean, `swift test --skip DecideLive` passes, and `swift test --filter DecideLive` passes with a key.

---

_📝 Noted on 2026-09-22 22:26:09-04:00 @ git:c568c93+local_

Finding 2026-09-22, before starting: the planned run-level test "a project config with DECIDE_MODEL = typesafe:jev-latest and no key anywhere exits 10 with the not-configured message" is not hermetic. `Jev(version:apiKey: nil)` and `OpenRouterAlpha` read their own key variable from `ProcessInfo.processInfo.environment` (library Jev.swift:58,75), not from the environment `Decide.run` receives. CI runs the whole suite in one `swift test` with TYPESAFE_API_KEY exported, so that test would reach the network there and get an answer, not exit 10. Replacement: the project file names an unknown provider, `DECIDE_MODEL = "nosuch:model"`, so the run exits 10 with the unknown-provider message naming "nosuch", which proves the value came from the file with no model built. "Env wins" becomes environment `DECIDE_MODEL = "other:x"` over that file, expecting the message to name "other". The key's flow from a home file to `ModelConfiguration.apiKey` is proved by a unit test on `ConfigFiles.environment(_:over:)` feeding `ModelConfiguration(environment:)`, since a run with an injected model never builds one. The by-hand live check still proves the real path end to end.

---

_📝 Noted on 2026-09-22 22:28:02-04:00 @ git:c568c93+local_

Design record 2026-09-22, filling what the Design section leaves open (the hermeticity note above changes the run-level tests):

- `paths` returns `public struct ConfigPaths: Equatable, Sendable { public var project: [String]; public var home: [String] }` instead of a tuple, so tests compare whole values. `load(paths: ConfigPaths, read:)`.
- Path normalization is lexical and pure: split on `/`, drop empty and `.` components, resolve `..` against the components so far (`..` at the root stays at the root), rejoin with one leading `/`. No filesystem call, so `/srv/app/x` works in a test and a symlinked temp directory is not rewritten. `currentDirectory`, `HOME`, and `XDG_CONFIG_HOME` all go through it before use. The root is `/`, and its file is `/.decide/config`.
- The walk: start at the normalized working directory; at each step, if HOME is set (non-blank after trimming) and the directory equals HOME, stop; else append `<dir>/.decide/config`; if the directory is `/`, stop; else go to the parent. So a directory under HOME stops before it, one outside HOME reaches `/`, and HOME itself yields nothing.
- `XDG_CONFIG_HOME` counts only when set, non-blank, and absolute (starts with `/`), as the XDG spec says; otherwise `<HOME>/.config`. The second home path is always `<HOME>/.decide/config`.
- `public enum ConfigReadError: Error, Equatable, Sendable { case unreadable, notUTF8 }`; `read: (String) throws(ConfigReadError) -> String?`. `load` maps `unreadable` to `ConfigError(path: path, line: 0, problem: "cannot read the file")` and `notUTF8` to `problem: "is not valid UTF-8"`, so the messages read `Error: <path>: cannot read the file` and `Error: <path>: is not valid UTF-8`.
- The trust rule's problem text: `DECIDE_MODEL_API_KEY is allowed only in the home config, not in a project's`, at the entry's line. The key names come from `ModelConfiguration.apiKeyVariable`.
- `environment(_:over:)`: copy the environment; for each config pair, when the environment's value is missing or blank after trimming whitespace and newlines, set it. Config values stay untrimmed.
- The real reader, private in `Decide.swift`, `readConfigFile(_ path: String) throws(ConfigReadError) -> String?`: `FileManager.default.fileExists(atPath:isDirectory:)` false → nil; a directory → `.unreadable`; `FileManager.default.contents(atPath:)` nil → `.unreadable`; `String(data:encoding: .utf8)` nil → `.notUTF8`.
- `Decide.run(arguments:environment:currentDirectory:model:stdout:stderr:)`, `currentDirectory: String? = nil` right after `environment`. After the `switch parsed` and before the model is built: `var environment = environment`; when `currentDirectory` is non-nil, compute paths, load with the real reader, and replace `environment` with `ConfigFiles.environment(environment, over: config)`; a thrown `ConfigError` prints `ExitCode.message(for:)` to stderr and returns `ExitCode.code(for:)`. Help and version never reach this point. `DecideCommand` passes `currentDirectory: FileManager.default.currentDirectoryPath`.
- `run` doc comment gains: "A `currentDirectory` turns on config files: `.decide/config` there and in each parent, then the home files, laid under `environment`. Without one, no file is read."
- Usage text, in the Environment section after the two variables, exactly:
  ```
  Config files: .decide/config in the working directory and its parents,
  then ~/.config/decide/config and ~/.decide/config. Lines of
  KEY = "value" with the same two keys. The nearest file wins, and the
  environment wins over every file.
  ```
  indented like the lines above it (two spaces).
- README, "Install and Setup": leave the existing block and its TODO alone. After the block add a second block and one paragraph, verbatim:
  ```sh
  # Or put the model in the project and the key in your home directory
  $ cat .decide/config
  DECIDE_MODEL = "typesafe:jev-latest"
  $ cat ~/.config/decide/config
  DECIDE_MODEL_API_KEY = "abc123..."
  ```
  `decide` reads `.decide/config` from the working directory and each parent up to your home directory, then `~/.config/decide/config` and `~/.decide/config`. The nearest file wins per key, and the environment wins over every file, so a `DECIDE_MODEL` exported in a shell profile turns every project file off; put durable defaults in the home file. `DECIDE_MODEL_API_KEY` may appear only in the home files, so a key never lands in a repository.
- TESTING.md, after the paragraph "This needs no key and no network. ...", a new paragraph verbatim: "The config tests read no real file. The loader's tests use an in-memory reader, and the run tests build a temp tree with `HOME` inside it, so the lookup never leaves the temp directory. `Decide.run` reads config only when given a working directory, and the tests that pass none stay as they were."
- Tests, `Tests/DecideCoreTests/ConfigFilesTests.swift` (`@Suite("ConfigFiles")`): the `paths`, `load`, and `environment` cases from the issue's Tests section, plus `ModelConfiguration(environment: ConfigFiles.environment([:], over: [DECIDE_MODEL: "typesafe:jev-latest", DECIDE_MODEL_API_KEY: "k"]))` having `apiKey == "k"` and `provider == .typesafe`. Run level, in `DecideRunTests.swift`, with a temp tree `<tmp>/home` as HOME and `<tmp>/home/proj/sub` as the working directory, `environment: ["HOME": home]`, cleaned up in a defer: (a) `<tmp>/home/proj/.decide/config` holding `DECIDE_MODEL = "nosuch:model"`, no model injected → exit 10, stderr contains `"nosuch"`, stdout empty; (b) a malformed project file → exit 10, stderr contains `<path>:1:`, stdout empty; (c) `DECIDE_MODEL_API_KEY` in the project file → exit 10, stderr contains the trust message and `<path>:<line>:`; (d) the key in `<home>/.config/decide/config` and the model in the project file, scripted model injected → exit 0 and the answer; (e) `environment: ["HOME": home, "DECIDE_MODEL": "other:x"]` over the `nosuch` project file → stderr contains `"other"` and not `"nosuch"`; (f) `currentDirectory: nil` with the same files on disk → exit 10 with the `DECIDE_MODEL is not set` message, proving nothing was read.
