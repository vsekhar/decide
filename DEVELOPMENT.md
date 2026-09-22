# Development

Notes for people who build `decide`. The README is for people who run it.
TESTING.md says how to run the tests.

## Build

```sh
swift build
swift build --build-tests -Xswiftc -warnings-as-errors
```

Keep the second command clean; it is the bar for every commit. The first
build fetches DecisionModels and swift-syntax. It takes minutes when the
SwiftPM cache is empty and about ten seconds after that.

## Layout

The executable is one file. All logic sits in the `DecideCore` library so
tests can use `@testable import DecideCore`; SwiftPM tests of executable
targets are awkward.

- `Sources/decide/DecideCommand.swift`: the `@main` type. It builds the two
  process streams, calls `Decide.run`, and exits.
- `Sources/DecideCore/Invocation.swift`: the parsed shape of one run.
- `Sources/DecideCore/CommandLineParser.swift`, `UsageError.swift`: the
  parser. It is hand-written because the grammar interleaves questions with
  their own flags, which swift-argument-parser cannot express.
- `Sources/DecideCore/Runner.swift`: one questionnaire for every question,
  one request, answers back in question order.
- `Sources/DecideCore/ModelConfiguration.swift`: `DECIDE_MODEL` and
  `DECIDE_MODEL_API_KEY` to a provider model.
- `Sources/DecideCore/ExitCode.swift`: every error to an exit code and a
  one-line message.
- `Sources/DecideCore/StandardStreams.swift`: stdout and stderr as
  `TextOutputStream` values.
- `Sources/DecideCore/Decide.swift`: `Decide.run` and the usage text.
- `Tests/DecideCoreTests/`: Swift Testing. One file per source file, plus
  `DecideRunTests` for a whole run with a scripted model and
  `DecideLiveTests` for the real model.

## Running the binary

`swift run decide ...` works, with one trap: SwiftPM expands an argument that
starts with `@` as a response file before the binary sees it, so
`--context @ticket.txt` breaks. Call the binary directly:

```sh
bin=$(swift build --show-bin-path)/decide
"$bin" --context @ticket.txt "Which team handles this ticket?" \
       --option shipping --option billing --option returns
```

The model and key come from the environment. TESTING.md says how to keep
them in `.env` and source it for one command.

## Issues

`.wip/` is the issue tracker: `wip ready` lists what is open, `wip show <id>`
reads one issue. The README is the spec; the tracker holds what is built,
what is next, and the design notes behind each change.

## Release

Users install with Homebrew from the tap at
https://github.com/vsekhar/homebrew-tap. A release is a tag here plus a
formula bump there. Tags are bare versions, like the library's.

1. Tag the commit, push it, and publish the release:

   ```sh
   git tag -a 0.2.0 -m "decide 0.2.0"
   git push origin main 0.2.0
   gh release create 0.2.0 --title "decide 0.2.0" --notes "..."
   ```

2. Point the formula at the new tag. Homebrew rewrites `url` and `sha256`
   in the tap's checkout, or edit those two lines by hand:

   ```sh
   brew tap vsekhar/tap
   brew bump-formula-pr --write-only --version 0.2.0 vsekhar/tap/decide
   ```

3. Check the formula, then commit and push from the tap's checkout:

   ```sh
   brew install --build-from-source vsekhar/tap/decide
   brew test decide
   brew audit --strict --online decide
   cd "$(brew --repository vsekhar/tap)"
   git commit -am "decide 0.2.0" && git push
   ```

Homebrew-core is the goal once this repository meets its notability bar:
225 stars, or 90 forks or watchers, for a self-submission. The formula
then moves there in a "decide 0.2.0 (new formula)" pull request.
