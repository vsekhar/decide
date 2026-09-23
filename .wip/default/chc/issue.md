---
priority: p2
type: feature
created: 2026-09-21T20:15:50-04:00
updated: 2026-09-22T23:11:59-04:00
---

# On-disk configuration: .decide/config files, a TOML subset, lookup from the working directory to the home, environment over files

## Summary

`decide` reads configuration from on-disk files as well as flags and the environment. A file is named `config` and lives in a `.decide` directory. The tool reads the working directory's, then each parent's up to the root or the home directory, then the home directory's own, and merges them with the nearest file winning per key. The environment wins over every file, and flags win over the environment. The format is TOML-shaped, but the tool parses it by hand with no dependency and accepts only `key = "value"` lines; every file it accepts is valid TOML, so a full parser can replace the hand-written one later without breaking a file. The keys, to start, are the two environment variable names, `DECIDE_MODEL` and `DECIDE_MODEL_API_KEY`, so a config file reads as a slice of environment. `--set-config KEY=VALUE` writes one key into a file and leaves the rest of it alone.

## User Story

A user puts `DECIDE_MODEL = "typesafe:jev-latest"` in a project's `.decide/config`, their key in `~/.config/decide/config`, and runs `decide` from any subdirectory of the project with no environment variables set. In CI, `DECIDE_MODEL` in the environment overrides the project's file without editing it. `decide --set-config DECIDE_MODEL="openrouter:typesafe/jev-1.13"` changes the home file's one line and keeps the comments around it.

## Design Decisions

Decided with the user on 2026-09-21.

- **Format: a TOML subset, parsed by hand.** Comments with `#`, blank lines, and `key = value` lines where the key is bare and the value is a basic or literal string. Tables, arrays, dotted keys, inline tables, multi-line strings, and non-string values are errors that name the construct. The invariant is that every accepted file is valid TOML 1.0. JSON stays for machine data (questionnaires, a later `--json`); this format is for what people edit.
- **Keys are the environment variable names.** `DECIDE_MODEL` and `DECIDE_MODEL_API_KEY`, nothing else yet. An unknown key is an error, which catches typos while the tool is young. Because the keys are the variable names, applying config is one step: lay the merged pairs under the process environment before `ModelConfiguration` reads it.
- **File name and places.** `.decide/config` in the working directory and each parent. The walk stops after checking the root, or before checking the home directory, whichever comes first; so a working directory under the home directory never reaches `/`, and a working directory outside it walks to `/`. The home directory is then read in its own step, in two places: `${XDG_CONFIG_HOME:-$HOME/.config}/decide/config`, then `$HOME/.decide/config`. When the working directory is the home directory, the walk checks nothing and the home step does the work, so no file is read twice. If `HOME` is unset, there are no home files and the walk goes to the root. This is the Cargo model (`.cargo/config.toml` up the tree, then `$CARGO_HOME`), also editorconfig's and npmrc's.
- **Merge: nearest wins per key.** A key set in a nearer file overrides the same key in a farther one; keys not set nearer fall through. Nothing can unset a key.
- **Precedence: flags, then environment, then files.** Environment over disk is git, Cargo, npm, gh, and twelve-factor: a file is durable and often shared, a variable lives in one shell session, a flag lives in one command. It is what lets CI override a committed project file. An environment variable that is set but blank counts as unset, matching `ModelConfiguration`, so config fills it. Consequence to document: exporting `DECIDE_MODEL` in a shell profile turns every project file off; durable defaults go in the home file.
- **Every problem is an error.** A malformed file, an unknown key, an unreadable file, or invalid UTF-8 anywhere in the chain stops the run with exit 10 and a message that names the file and line. The user resolves it. No warnings.
- **Trust boundary.** Walking up reads files a cloned repository controls. `DECIDE_MODEL` is harmless there: cost, not exfiltration, since the provider URL is fixed. A key in a project file is a leak waiting for a commit, and the rule should exist before any key can name a path or a command: `DECIDE_MODEL_API_KEY` is read only from the two home files, and in a project file it is an error.
- **Writing keeps the file.** `--set-config` edits one line and leaves every other byte, comments included, the `git config` model. It writes the home file by default (like `npm config set` and `gh config set`); `--project` writes `./.decide/config`. The flag runs alone, because a bare token is a question in this tool and `decide config set` would be asked of the model.

## Out of Scope

- Full TOML: tables, arrays, numbers, dates, multi-line strings.
- Other keys. A `min_confidence` or `quiet` default changes exit codes for scripts and needs its own design.
- `--model` and `--model-api-key` flags. The README's Setup section names them and nothing has built or filed them; the precedence rule here holds once they exist, because flags are applied last.
- `--show-config`, `--unset-config`, a system-wide `/etc/decide/config`, a permissions warning on a world-readable home file holding a key, and a keychain or command hook for keys. Each is a natural follow-up.
- Named or composite contexts, `--fallback`, `--exit`.

## Testing Strategy

The parser is pure and tested on text. The lookup's path computation is pure and tested on strings. The loader takes an injected file reader, so its tests use an in-memory map and never touch the disk. Run-level tests build a temp tree with a fake `HOME` inside it, so the walk cannot leave the temp directory, and `Decide.run` skips config entirely unless a working directory is passed, so every existing test stays hermetic. One live check by hand proves a real run picks the model up from a file with the environment cleared.

## Children

| ID | Title | Blocked on |
|---|---|---|
| mia | Parse `.decide/config`: the TOML subset | - |
| rvj | Read config from the working directory upward and the home directory, apply it under the environment | mia |
| jq1 | Add `--set-config KEY=VALUE` with `--project` | mia, rvj |

Start with mia. rvj is the feature; jq1 follows.

---

_📝 Noted on 2026-09-22 23:11:59-04:00 @ git:6253340+local_

Known limitation 2026-09-22, from rvj's verification: path comparison is lexical by design, so if HOME is a symlink path while the working directory is physical (or the reverse), the walk never meets HOME, climbs to the root, and reads the real home's .decide/config as a project file, where a key line is then refused. No claim is made for symlinked homes; a later issue could resolve both paths with the filesystem before comparing.
