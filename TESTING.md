# Testing

All tests use Swift Testing. Run them from the package root with Xcode 26.6
or later.

## Everything but the live suite

```sh
swift test --skip DecideLive
```

This needs no key and no network. A scripted model from
`DecisionModelsTesting` stands in for the real one, and the run tests
inject `String` streams for stdout and stderr.

Build with warnings as errors before you commit:

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
```

## One suite at a time

Suite names match the source files: `CommandLineParser`, `Runner`,
`ModelConfiguration`, `ExitCode`, `DecideRun`, and `DecideLive`.

```sh
swift test --filter CommandLineParser
```

## The live test against the real model

The `DecideLive` suite runs the README's team question through `Decide.run`
against the model that `DECIDE_MODEL` names. It sends one request. It reads
`DECIDE_MODEL` and a key from the environment, either `DECIDE_MODEL_API_KEY`
or the provider's own `TYPESAFE_API_KEY` or `OPENROUTER_API_KEY`, and
**fails** when either is absent. It never skips, because a green run that
talked to nothing says nothing.

Put the variables in `.env`, which git ignores, and source it for one
command:

```sh
set -a; . ./.env; set +a; swift test --filter DecideLive
```

`.env` looks like this:

```sh
DECIDE_MODEL=typesafe:jev-latest
DECIDE_MODEL_API_KEY=...
```

Do not print the key, and do not commit `.env`.

## The whole suite

```sh
set -a; . ./.env; set +a; swift test
```

## What the suite cannot see

The run tests only watch the streams they inject. A stray write to the
process's real stdout, from this package or from the library, would not
fail a test, and it would corrupt every answer a script reads. The binary
is the check: on every non-zero exit, stdout must be empty.

```sh
bin=$(swift build --show-bin-path)/decide
env -u DECIDE_MODEL "$bin" --context x "Q?" --option a --option b 2>/dev/null | wc -c   # 0
```
