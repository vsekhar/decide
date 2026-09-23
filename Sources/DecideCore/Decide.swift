import DecisionModels
import Foundation

/// The entry point the executable calls.
public enum Decide {
    /// The text `--help` prints.
    public static let usage = """
        decide \(version)

        Usage: decide [--context <text>] "<question>" [<flags>] ["<question>" [<flags>]]...

        Ask a decision model one or more questions, about one context or none.
        The answer to each question prints on its own line: the id of the chosen
        option or level, or yes or no. A question with no --option or --level is
        a yes/no question; --yes and --no set what it prints.

          --context <text>       The text to judge. Optional: a question that carries
                                 its own facts needs none.
          --context @<path>      Read the text from a file.
          "<question>"           A question. The flags after it belong to it.
          --option <id>          An option the model can choose. The question is a choice.
          --option <id>=<text>   An option with a description.
          --level <id>           A level on a scale, low to high. The question is a rating.
          --level <id>=<text>    A level with a description.
          --yes <value>          What a yes/no question prints for yes. Default: yes.
          --yes <value>=<text>   The value, and what counts as yes.
          --no <value>           What a yes/no question prints for no. Default: no.
          --no <value>=<text>    The value, and what counts as no.
          --min-confidence <n>   The confidence an answer needs, from 0 to 1. Below it
                                 the run is unsure and exits 2. On a yes/no question, n
                                 means P(yes) at least (1 + n) / 2 for yes.
          --quiet, -q            Print no answer. Only with one yes/no question.
          --help, -h             Print this text.
          --version              Print the version and exit. Takes no other arguments.

        Environment:
          DECIDE_MODEL           provider:model, for example typesafe:jev-latest
                                 or openrouter:typesafe/jev-1.13
          DECIDE_MODEL_API_KEY   The API key. When unset, the provider reads its own
                                 variable: TYPESAFE_API_KEY or OPENROUTER_API_KEY.

        Exit codes: 0 decided, 2 unsure, 10 setup or input error, 11 remote error.
        One yes/no question answers with its exit code too: 0 yes, 1 no, like grep.
        """

    /// Runs the tool and returns the process exit code.
    ///
    /// `arguments` are the command line after the program name. A `model`
    /// replaces the one the environment names, so tests inject a scripted
    /// one. Answers go to `stdout`, one per line, unless the run is quiet;
    /// everything else goes to `stderr`.
    public static func run(
        arguments: [String],
        environment: [String: String],
        model: (any DecisionModel)? = nil,
        stdout: inout some TextOutputStream,
        stderr: inout some TextOutputStream
    ) async -> Int32 {
        let parsed: ParseResult
        do {
            parsed = try CommandLineParser.parse(arguments)
        } catch {
            report(error, to: &stderr)
            return ExitCode.setup
        }
        let invocation: Invocation
        switch parsed {
        case .help:
            print(usage, to: &stdout)
            return ExitCode.decided
        case .version(let alone):
            guard alone else {
                print(version, to: &stderr)
                print("Error: --version takes no other arguments", to: &stderr)
                return ExitCode.setup
            }
            print(version, to: &stdout)
            return ExitCode.decided
        case .run(let parsedInvocation):
            invocation = parsedInvocation
        }

        let decisionModel: any DecisionModel
        do {
            decisionModel = try model ?? ModelConfiguration(environment: environment).makeModel()
        } catch {
            print(ExitCode.message(for: error), to: &stderr)
            return ExitCode.code(for: error)
        }

        let context: String?
        if let source = invocation.context {
            guard let loaded = loadContext(source, stderr: &stderr) else { return ExitCode.setup }
            context = loaded
        } else {
            context = nil
        }

        let outcomes: [Outcome]
        do {
            let session = DecisionSession(model: decisionModel)
            outcomes = try await Runner.decide(
                invocation.questions, about: context, using: session
            )
        } catch {
            print(ExitCode.message(for: error), to: &stderr)
            return ExitCode.code(for: error)
        }

        if !invocation.quiet {
            for outcome in outcomes {
                print(outcome.answer, to: &stdout)
            }
        }
        return exitCode(for: outcomes, questions: invocation.questions)
    }

    /// The code a decided run returns. One yes/no question answers with its
    /// exit code as well, like grep: 0 for yes, 1 for no. Every other run
    /// returns 0.
    private static func exitCode(for outcomes: [Outcome], questions: [Question]) -> Int32 {
        guard questions.count == 1, case .verdict(let yes, _) = questions[0].kind,
              let outcome = outcomes.first
        else {
            return ExitCode.decided
        }
        return outcome.answer == yes.id ? ExitCode.decided : ExitCode.no
    }

    /// Prints a usage error and the usage text to `stderr`.
    private static func report(_ error: UsageError, to stderr: inout some TextOutputStream) {
        print(ExitCode.message(for: error), to: &stderr)
        print("", to: &stderr)
        print(usage, to: &stderr)
    }

    /// Reads the context. `.text` is the text itself; `.file` is read as
    /// UTF-8. Prints the reason to `stderr` and returns nil when the file
    /// does not read.
    private static func loadContext(
        _ source: ContextSource,
        stderr: inout some TextOutputStream
    ) -> String? {
        switch source {
        case .text(let text):
            return text
        case .file(let path):
            do {
                return try String(contentsOfFile: path, encoding: .utf8)
            } catch {
                print(
                    "Error: cannot read context file \"\(path)\": \(error.localizedDescription)",
                    to: &stderr
                )
                return nil
            }
        }
    }
}
