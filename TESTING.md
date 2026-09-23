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

The config tests read no real file. The loader's tests use an in-memory
reader, and the run tests build a temp tree with `HOME` inside it, so the
lookup never leaves the temp directory. `Decide.run` reads config only when
given a working directory, and the tests that pass none stay as they were.

Build with warnings as errors before you commit:

```sh
swift build --build-tests -Xswiftc -warnings-as-errors
```

## One suite at a time

Suite names match the source files: `CommandLineParser`, `Invocation`,
`Runner`, `ModelConfiguration`, `ConfigFile`, `ConfigFiles`, `ExitCode`,
`DecideRun`, and `DecideLive`.

```sh
swift test --filter CommandLineParser
```

## The live tests against the real model

The `DecideLive` suite runs README examples through `Decide.run` against
the model that `DECIDE_MODEL` names. It reads `DECIDE_MODEL` and a key from
the environment, either `DECIDE_MODEL_API_KEY` or the provider's own
`TYPESAFE_API_KEY` or `OPENROUTER_API_KEY`, and **fails** when either is
absent. It never skips, because a green run that talked to nothing says
nothing.

Keep the live suite short, for time and not for money. Decision model
requests are cheap, thousands per penny, so cost sets no limit. Each
request adds a network round trip to every CI job and every local run, so
a live test earns its place only when a scripted model cannot prove the
same thing.

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

## Continuous integration

`.github/workflows/ci.yml` runs on every push, on pull requests from forks,
and on demand. The CI badge in the README shows its result on `main`, and
the codecov badge shows the line coverage of `main`.

| Job | Runner | What it runs |
|---|---|---|
| macOS tests | `macos-26`, Xcode 26.6 | the whole suite, `DecideLive` included, in one run with warnings as errors and coverage on, then the coverage upload |
| Linux tests | `ubuntu-latest`, `swift:6.3.3-noble` container | the whole suite, `DecideLive` included, with warnings as errors |

The tests run in one `swift test` because each run with coverage clears the
coverage of the run before it. To reproduce the macOS step:

```sh
set -a; . ./.env; set +a
swift test -Xswiftc -warnings-as-errors --enable-code-coverage
```

CI sets `DECIDE_MODEL` to `typesafe:jev-latest` in the workflow and passes
`TYPESAFE_API_KEY` from a secret. It sets no `DECIDE_MODEL_API_KEY`, so the
tool reads the provider's own variable. Each job runs the live suite once.

The build log may show pairs of `Internal Error: DecodingError` and `LLVM
Profile Error` lines from the library's macro plugin. They are harmless;
[the library's TESTING.md](https://github.com/vsekhar/DecisionModels/blob/main/TESTING.md)
explains them.

The coverage report holds only this package's sources. Tests, the library,
swift-syntax, and the generated test runner are left out, because the export
names the `Sources` folder. The `decide` target is absent too: the tests do
not link the executable, so the report covers `DecideCore`. Git ignores the
`coverage.lcov` the command writes.

```sh
bin=$(swift build --show-bin-path)
xcrun llvm-cov export -format=lcov \
  -instr-profile "$bin/codecov/default.profdata" \
  "$bin/decidePackageTests.xctest/Contents/MacOS/decidePackageTests" \
  "$PWD/Sources" > coverage.lcov
```

Two repository secrets feed the jobs. Set each once from the package root:

- `TYPESAFE_API_KEY` for the live suite. `gh secret set TYPESAFE_API_KEY`
  prompts for the value, so paste the key. Do not use `gh secret set -f
  .env`: `.env` holds more than that key, and every line would become a
  secret. Without the key, the live suite fails on both jobs, as it does
  locally.
- `CODECOV_TOKEN` for the upload. Add the repository at codecov.io, copy
  the token it shows, and run `gh secret set CODECOV_TOKEN`. A failed
  upload fails the job, so a bad token shows at once.

A pull request from a branch in this repository runs on its push, not again
as a pull request. A pull request from a fork runs both jobs with
`--skip DecideLive` and without the upload, because forks get no secrets.

The Linux job is the one check that this package builds and passes on
Linux. Every Foundation call it makes exists in swift-corelibs-foundation.
One path has no test on either platform: a context file that is not valid
UTF-8. `String(contentsOfFile:encoding:)` throws on both, but the error's
code and message may differ, and the one test of a bad context file checks
a missing file, not a corrupt one. The Linux job would not catch a
difference there.

To run the offline suite in the same image on a Mac, install Docker and run
this from the package root. The tag pins the Swift version that Xcode 26.6
ships, 6.3.3, so both platforms build with the same compiler. The scratch
path keeps the Linux build products apart from the Mac's:

```sh
docker run --rm -v "$PWD":/pkg -w /pkg swift:6.3.3-noble \
  swift test -Xswiftc -warnings-as-errors --scratch-path .build/linux \
  --skip DecideLive
```

To add the live suite, pass the model and the key in from the environment:

```sh
set -a; . ./.env; set +a
docker run --rm -e DECIDE_MODEL -e DECIDE_MODEL_API_KEY \
  -v "$PWD":/pkg -w /pkg swift:6.3.3-noble \
  swift test -Xswiftc -warnings-as-errors --scratch-path .build/linux
```

## What the suite cannot see

The run tests only watch the streams they inject. A stray write to the
process's real stdout, from this package or from the library, would not
fail a test, and it would corrupt every answer a script reads. The binary
is the check: on every exit of 2 or more, stdout must be empty. One yes/no
question exits 0 or 1 with its answer on stdout, and with nothing on stdout
under `-q`.

```sh
bin=$(swift build --show-bin-path)/decide
env -u DECIDE_MODEL "$bin" --context x "Q?" --option a --option b 2>/dev/null | wc -c   # 0
```

`--version` with any other argument is a usage error, so the version goes
to stderr and stdout stays empty there too:

```sh
"$bin" --version --context x; echo $?                 # the version and the error, then 10
"$bin" --version --context x 2>/dev/null | wc -c      # 0
```

With `.env` sourced, one yes/no question exits 0 or 1 and prints nothing
under `-q`:

```sh
out=$(mktemp)
"$bin" --context "free money, act now" "Is this message spam?" -q >"$out" 2>/dev/null
echo $?           # 0 yes, 1 no
wc -c < "$out"    # 0
```
