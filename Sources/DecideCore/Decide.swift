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

          --context <text>               Optional context for question(s).
          --context @<path>              Context from file.
          --context <name>=<text>        A named context, as a field of one JSON object.
          --context <name>=@<path>       A named context from a file. With more than one
                                         --context, every one needs a name.
          "<question>"                   A question. The flags after it belong to it.
          --option <label>[=explanation] An option the model can choose, optional explanation.
          --level <label>[=explanation]  A level on a scale, low to high, optional explanation.
          --yes <label>[=explanation]    Label and optional explanation for "yes"
          --no <label>[=explanation]     Label and optional explanation for "no"
          --min-confidence <n>           The confidence an answer needs, from 0 to 1. Below it
                                         the run is unsure and exits 2. On a yes/no question, n
                                         means P(yes) at least (1 + n) / 2 for yes.
          --quiet, -q                    Print no answer. Only with one yes/no question.
          --model <model>                The model for this run, provider:model. Wins over
                                         the environment and every config file.
          --api-key <key>                The API key for this run. Wins over the environment
                                         and every config file.
          --set-config                   Write --model and --api-key to the home config and exit.
          --project                      With --set-config, write ./.decide/config instead.
          --help, -h                     Print this text.
          --version                      Print the version and exit. Takes no other arguments.

        Environment:
          DECIDE_MODEL                   provider:model, for example typesafe:jev-latest
                                         or openrouter:typesafe/jev-1.13
          DECIDE_MODEL_API_KEY           The API key. When unset, the provider reads its own
                                         variable: TYPESAFE_API_KEY or OPENROUTER_API_KEY.

          Config files: .decide/config in the working directory and its parents,
          then ~/.config/decide/config and ~/.decide/config. Lines of
          KEY = "value" with the same two keys. The nearest file wins, and the
          environment wins over every file. --model and --api-key win over both.
          --set-config edits one line and keeps the rest.

        Exit codes: 0 decided, 2 unsure, 10 setup or input error, 11 remote error.
        One yes/no question answers with its exit code too: 0 yes, 1 no, like grep.
        """

    /// Runs the tool and returns the process exit code.
    ///
    /// `arguments` are the command line after the program name. A `model`
    /// replaces the one the environment names, so tests inject a scripted
    /// one. Answers go to `stdout`, one per line, unless the run is quiet;
    /// everything else goes to `stderr`.
    ///
    /// A `currentDirectory` turns on config files: `.decide/config` there
    /// and in each parent, then the home files, laid under `environment`.
    /// Without one, no file is read. A `--set-config` run writes one config
    /// file and reads none.
    public static func run(
        arguments: [String],
        environment: [String: String],
        currentDirectory: String? = nil,
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
        case .setConfig(let request):
            return setConfig(
                request,
                environment: environment,
                currentDirectory: currentDirectory,
                stderr: &stderr
            )
        case .run(let parsedInvocation):
            invocation = parsedInvocation
        }

        var environment = environment
        if let currentDirectory {
            do {
                let paths = ConfigFiles.paths(
                    currentDirectory: currentDirectory, environment: environment
                )
                let config = try ConfigFiles.load(paths: paths, read: readConfigFile)
                environment = ConfigFiles.environment(environment, over: config)
            } catch {
                print(ExitCode.message(for: error), to: &stderr)
                return ExitCode.code(for: error)
            }
        }
        environment = invocation.applied(to: environment)

        let decisionModel: any DecisionModel
        do {
            decisionModel = try model ?? ModelConfiguration(environment: environment).makeModel()
        } catch {
            print(ExitCode.message(for: error), to: &stderr)
            return ExitCode.code(for: error)
        }

        let state: State?
        if let context = invocation.context {
            guard let loaded = loadState(context, stderr: &stderr) else { return ExitCode.setup }
            state = loaded
        } else {
            state = nil
        }

        let outcomes: [Outcome]
        do {
            let session = DecisionSession(model: decisionModel)
            outcomes = try await Runner.decide(
                invocation.questions, about: state, using: session
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

    /// Writes what `--set-config` names into a config file and gives the
    /// exit code. Success prints nothing. Every failure prints one line to
    /// `stderr` and leaves the file as it was.
    private static func setConfig(
        _ request: SetConfig,
        environment: [String: String],
        currentDirectory: String?,
        stderr: inout some TextOutputStream
    ) -> Int32 {
        let pairs: [(key: String, value: String)]
        let path: String
        do {
            pairs = try settings(of: request)
            path = try target(
                of: request, environment: environment, currentDirectory: currentDirectory
            )
        } catch {
            print(ExitCode.message(for: error), to: &stderr)
            return ExitCode.setup
        }
        do {
            let text = try readConfigFile(path) ?? ""
            let edited = try ConfigFile.setting(pairs, in: text, path: path)
            try writeConfigFile(edited, to: path, isHome: !request.project)
        } catch let error as ConfigReadError {
            print(ExitCode.message(for: ConfigFiles.error(error, at: path)), to: &stderr)
            return ExitCode.setup
        } catch let error as ConfigError {
            print(ExitCode.message(for: error), to: &stderr)
            return ExitCode.setup
        } catch {
            let failure = ConfigError(path: path, line: 0, problem: error.localizedDescription)
            print(ExitCode.message(for: failure), to: &stderr)
            return ExitCode.setup
        }
        return ExitCode.decided
    }

    /// The keys and values a `--set-config` run writes, in order. The model
    /// goes through `ModelConfiguration` first, so a malformed one or an
    /// unknown provider never reaches a file.
    private static func settings(
        of request: SetConfig
    ) throws(ConfigurationError) -> [(key: String, value: String)] {
        var pairs: [(key: String, value: String)] = []
        if let model = request.model {
            _ = try ModelConfiguration(environment: [ModelConfiguration.modelVariable: model])
            pairs.append((ModelConfiguration.modelVariable, model))
        }
        if let apiKey = request.apiKey {
            pairs.append((ModelConfiguration.apiKeyVariable, apiKey))
        }
        return pairs
    }

    /// The file a `--set-config` run writes: the home config, or the
    /// working directory's `.decide/config` with `--project`.
    private static func target(
        of request: SetConfig,
        environment: [String: String],
        currentDirectory: String?
    ) throws(UsageError) -> String {
        if request.project {
            guard let currentDirectory else {
                throw UsageError("--project has no working directory")
            }
            return ConfigFiles.projectFile(in: currentDirectory)
        }
        guard let path = ConfigFiles.homeFile(environment: environment) else {
            throw UsageError("HOME is not set, so there is no home config")
        }
        return path
    }

    /// Writes the text to `path` through a temporary file in the same
    /// directory, which it renames over the target, so a failure leaves the
    /// old file as it was. The home config is the owner's alone: mode 0700
    /// on the directories it makes, and the file is created at 0600, so no
    /// one else can read a key even for an instant.
    private static func writeConfigFile(_ text: String, to path: String, isHome: Bool) throws {
        let url = URL(fileURLWithPath: path)
        let directory = url.deletingLastPathComponent()
        let attributes: [FileAttributeKey: Any]? = isHome ? [.posixPermissions: 0o700] : nil
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: attributes
        )
        let temporary = directory.appendingPathComponent(".config.\(UUID().uuidString).tmp")
        do {
            let descriptor = open(
                temporary.path, O_WRONLY | O_CREAT | O_EXCL, isHome ? 0o600 : 0o644
            )
            guard descriptor >= 0 else { throw posixError() }
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: Data(text.utf8))
            try handle.close()
            guard rename(temporary.path, path) == 0 else { throw posixError() }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }

    /// The last POSIX call's failure, with the system's own reason as its
    /// message.
    private static func posixError() -> NSError {
        let code = errno
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
        )
    }

    /// Reads a config file. Gives nil when there is no file at `path`. A
    /// directory there, or bytes that do not come back, is `.unreadable`,
    /// and bytes that are not UTF-8 are `.notUTF8`. It decodes the bytes
    /// itself, because `String(contentsOfFile:)` gives a different error
    /// for bad UTF-8 on each platform.
    private static func readConfigFile(_ path: String) throws(ConfigReadError) -> String? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return nil
        }
        guard !isDirectory.boolValue else { throw .unreadable }
        guard let data = FileManager.default.contents(atPath: path) else { throw .unreadable }
        guard let text = String(data: data, encoding: .utf8) else { throw .notUTF8 }
        return text
    }

    /// Reads the run's context into the state the model sees. One context is
    /// its text. Named contexts are one object, each field the text of the
    /// context of that name, read in command-line order. Prints the reason to
    /// `stderr` and returns nil when a file does not read.
    private static func loadState(
        _ context: Context,
        stderr: inout some TextOutputStream
    ) -> State? {
        switch context {
        case .single(let source):
            guard let text = loadContext(source, stderr: &stderr) else { return nil }
            return .text(text)
        case .named(let contexts):
            // Assignment, not `Dictionary(uniqueKeysWithValues:)`, which traps
            // on a repeated name. The parser keeps names unique, but
            // `Invocation` is public, so the last one wins instead.
            var fields: [String: State] = [:]
            for context in contexts {
                guard let text = loadContext(context.source, stderr: &stderr) else { return nil }
                fields[context.name] = .text(text)
            }
            return .object(fields)
        }
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
