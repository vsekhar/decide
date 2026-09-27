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
        --name, --stats, and --distribution add to that line.

          --context <text>               Optional context for question(s).
          --context @<path>              Context from file.
          --context -                    Context from standard input.
          --context <name>=<text>        A named context, as a field of one JSON object.
          --context <name>=@<path>       A named context from a file. With more than one
                                         --context, every one needs a name.
          --context <name>=-             A named context from standard input.
          --context-json <json>          Context parsed as JSON, so the model sees its structure:
                                         objects, arrays, numbers, and booleans, not one string.
                                         Takes @<path> and - like --context.
          --context-json <name>=<json>   A named JSON context, in the same three forms.
          --questions @<path>            Questions from a file, in the flag's place: a JSON
                                         file when it starts with {, else questions and their
                                         flags split like a command line, # starting a comment.
          --questions <text>             The same, from the text itself.
          --questions -                  The same, from standard input. One - per run:
                                         standard input reads once.
          "<question>"                   A question. The flags after it belong to it.
          --option <label>[=explanation] An option the model can choose, optional explanation.
          --level <label>[=explanation]  A level on a scale, low to high, optional explanation.
          --yes <label>[=explanation]    Label and optional explanation for "yes"
          --no <label>[=explanation]     Label and optional explanation for "no"
          --min-confidence <n>           The confidence an answer needs, from 0 to 1. Below it
                                         the answer prints empty, the run exits 2, and stderr
                                         names the question. On a yes/no question, n means
                                         P(yes) at least (1 + n) / 2 for yes.
          --fallback <value>             What this question prints when its answer is below
                                         its bar, or when the model server fails. A yes/no
                                         question's fallback is its --yes or --no value.
          --name <name>                  The question's name, an identifier: its id on the wire
                                         and in --json, and its line prints as name=answer.
          --stats                        Add a field to this question's line after a tab:
                                         confidence:<n> probability:<n>, and for a rating
                                         score:<n>, its expected level index. Levels count
                                         from 0 in declared order. Three decimals; the
                                         --min-confidence bar tests the exact value.
                                         Not with --quiet.
          --distribution                 --stats, then one field per option, level, or side
                                         as id:probability, in declared order; a level as
                                         id[index]:probability. Not with --quiet.
          --quiet, -q                    Print no answer. Only with one yes/no question.
          --json                         Print one JSON object keyed by question name, with
                                         each answer's kind, confidence, and probabilities.
                                         Not with --quiet.
          --each                         Decide once per line of standard input: each line is
                                         the event the - context holds, and each event prints
                                         its own lines, one with --json. Blank lines are
                                         skipped, and stderr names the input line. Not with
                                         --quiet or --questions -.
          --model <model>                The model for this run, provider:model. Wins over
                                         the environment and every config file.
          --api-key <key>                The API key for this run. Wins over the environment
                                         and every config file. --api-key - reads the key from
                                         standard input: a prompt with echo off at a terminal,
                                         one line from a pipe. --api-key with no value does the
                                         same.
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
        With --each, the final code is the highest any event produced.
        """

    /// Runs the tool and returns the process exit code.
    ///
    /// `arguments` are the command line after the program name. A `model`
    /// replaces the one the environment names, so tests inject a scripted
    /// one. Answers go to `stdout`, one per line, unless the run is quiet;
    /// everything else goes to `stderr`. An answer below its bar prints
    /// empty; the run reports it on `stderr` and exits 2 after every line has
    /// printed. A question's `--fallback` prints instead of an unsure answer
    /// and counts as decided. When the model server fails and every question
    /// has a fallback, the fallbacks print and the run is decided; otherwise
    /// nothing prints and the code is 11. Before it parses the line, it reads
    /// each `--questions` file and puts its questions in the flag's place.
    /// `-` as a `--context`, `--questions`, or `--api-key` value reads
    /// standard input, once per run; the key is one line, asked for with a
    /// prompt and echo off at a terminal. A `--context-json` value, whatever
    /// its form, is parsed as JSON before the model sees it. `--each` runs
    /// the questions once per line of standard input, which the `-` context
    /// holds; each event prints its own lines, stderr names the input line,
    /// and the code is the highest any event produced.
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
        standardInput: any StandardInputReading = StandardInput(),
        stdout: inout some TextOutputStream,
        stderr: inout some TextOutputStream
    ) async -> Int32 {
        // Records the read, so the check after `parse` can refuse a second
        // `-` on the line.
        var standardInputWasRead = false
        func readStandardInput() throws(ConfigReadError) -> String {
            standardInputWasRead = true
            return try standardInput.readToEnd()
        }
        let parsed: ParseResult
        do {
            let items = try QuestionFile.expanding(
                arguments, read: readConfigFile, standardInput: readStandardInput
            )
            parsed = try CommandLineParser.parse(items: items)
            if standardInputWasRead, case .run(let invocation) = parsed,
               invocation.readsStandardInput {
                throw UsageError(CommandLineParser.standardInputTwice)
            }
        } catch let error as UsageError {
            report(error, to: &stderr)
            return ExitCode.setup
        } catch {
            print(ExitCode.message(for: error), to: &stderr)
            return ExitCode.setup
        }
        var invocation: Invocation
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
                standardInput: standardInput,
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
        if invocation.apiKey == .standardInput {
            do {
                invocation.apiKey = .value(try readAPIKey(from: standardInput, stderr: &stderr))
            } catch {
                print(ExitCode.message(for: error), to: &stderr)
                return ExitCode.setup
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

        if invocation.each {
            return await stream(
                invocation,
                model: decisionModel,
                standardInput: standardInput,
                stdout: &stdout,
                stderr: &stderr
            )
        }

        let state: State?
        if let context = invocation.context {
            do {
                state = try loadState(context, standardInput: readStandardInput)
            } catch {
                print(ExitCode.message(for: error), to: &stderr)
                return ExitCode.setup
            }
        } else {
            state = nil
        }

        return await decide(
            invocation,
            about: state,
            using: DecisionSession(model: decisionModel),
            line: nil,
            stdout: &stdout,
            stderr: &stderr
        ).code
    }

    /// Runs the questions about the state and prints the answers: the whole
    /// of a plain run, or one event of a stream. `line` is the event's input
    /// line number in a stream, and nil in a plain run. Every stderr line of
    /// an event starts with `line N: `. Returns the exit code. A plain run
    /// gives the answer's code, as `run` describes. In a stream a decided
    /// event is 0 whatever it answered, so is a remote error every fallback
    /// covers, and `stops` is true for a model error that is the run's, not
    /// the event's: one whose code is `ExitCode.setup`, except a context too
    /// large for the model, which is the event's alone. A remote error no
    /// fallback covers, or a context too large for the model, prints an
    /// error record under `--json` in a stream, so the event still prints
    /// one line, and nothing in a plain run.
    private static func decide(
        _ invocation: Invocation,
        about state: State?,
        using session: DecisionSession,
        line: Int?,
        stdout: inout some TextOutputStream,
        stderr: inout some TextOutputStream
    ) async -> (code: Int32, stops: Bool) {
        let prefix = line.map { "line \($0): " } ?? ""
        let outcomes: [Outcome]
        do {
            outcomes = try await Runner.decide(
                invocation.questions, about: state, using: session
            )
        } catch {
            print(prefix + ExitCode.message(for: error), to: &stderr)
            let code = ExitCode.code(for: error)
            let fallbacks = invocation.questions.map(\.fallback)
            let perEvent = code == ExitCode.remote || isEventError(error)
            guard code == ExitCode.remote, !fallbacks.contains(nil) else {
                if line != nil, perEvent, invocation.json {
                    let record = JSONOutput.errorLine(
                        for: invocation.questions, message: ExitCode.reason(for: error)
                    )
                    print(record, terminator: "", to: &stdout)
                }
                return (code, line != nil && !perEvent)
            }
            if invocation.json {
                print(JSONOutput.fallbackLine(for: invocation.questions), terminator: "", to: &stdout)
            } else if !invocation.quiet {
                for question in invocation.questions {
                    print(PlainOutput.fallbackLine(for: question), to: &stdout)
                }
            }
            let fallbackCode = line == nil
                ? exitCode(for: fallbacks, questions: invocation.questions) : ExitCode.decided
            return (fallbackCode, false)
        }

        if invocation.json {
            let json = JSONOutput.line(for: invocation.questions, outcomes: outcomes)
            print(json, terminator: "", to: &stdout)
        } else if !invocation.quiet {
            for (question, outcome) in zip(invocation.questions, outcomes) {
                print(PlainOutput.line(for: question, outcome: outcome), to: &stdout)
            }
        }
        let printed = zip(invocation.questions, outcomes).map(Runner.printedAnswer)
        let unsure = Runner.unsureQuestions(in: invocation.questions, outcomes: outcomes)
        if !unsure.isEmpty {
            print(prefix + Unsure.report(unsure), to: &stderr)
        }
        guard !printed.contains(nil) else { return (ExitCode.unsure, false) }
        let code = line == nil
            ? exitCode(for: printed, questions: invocation.questions) : ExitCode.decided
        return (code, false)
    }

    /// Whether a model error belongs to the event alone in a stream, so the
    /// stream goes on. A context too large for the model depends on the
    /// event's size. Every other error whose code is setup is the run's, the
    /// same for every event, so it stops the stream.
    private static func isEventError(_ error: any Error) -> Bool {
        guard case .contextSizeExceeded = error as? DecisionError else { return false }
        return true
    }

    /// Runs the questions once per line of standard input, in order, through
    /// one session. The `-` context holds each line. A blank line is skipped
    /// but counted, so stderr names the line in the input. A bad line, one
    /// that is not UTF-8 or not valid JSON under `--context-json`, is an
    /// error for that event alone, and so is a context too large for the
    /// model. Every other setup error from the model is the run's, so it
    /// stops the stream, as does standard input that does not read. Returns
    /// the highest code any event produced, 0 for an empty stream.
    private static func stream(
        _ invocation: Invocation,
        model: any DecisionModel,
        standardInput: any StandardInputReading,
        stdout: inout some TextOutputStream,
        stderr: inout some TextOutputStream
    ) async -> Int32 {
        guard let context = invocation.context else {
            let error = UsageError(CommandLineParser.eachNeedsStandardInput)
            print(ExitCode.message(for: error), to: &stderr)
            return ExitCode.setup
        }
        let base: Context
        do {
            base = try readingFiles(in: context)
        } catch {
            print(ExitCode.message(for: error), to: &stderr)
            return ExitCode.setup
        }

        let session = DecisionSession(model: model)
        var highest = ExitCode.decided
        var number = 0
        while true {
            let line: String
            do {
                guard let read = try standardInput.readLine() else { break }
                line = read
            } catch .notUTF8 {
                number += 1
                reportBadLine(
                    ContextLoadError.lineNotUTF8, line: number, invocation: invocation,
                    stdout: &stdout, stderr: &stderr
                )
                highest = max(highest, ExitCode.setup)
                continue
            } catch {
                print(ExitCode.message(for: ContextLoadError.unreadableInput), to: &stderr)
                return max(highest, ExitCode.setup)
            }
            number += 1
            guard !line.allSatisfy(\.isWhitespace) else { continue }

            let state: State
            do {
                state = try loadState(
                    base.replacingStandardInput(with: line), standardInput: { line }
                )
            } catch {
                reportBadLine(
                    error, line: number, invocation: invocation,
                    stdout: &stdout, stderr: &stderr
                )
                highest = max(highest, ExitCode.setup)
                continue
            }
            let (code, stops) = await decide(
                invocation,
                about: state,
                using: session,
                line: number,
                stdout: &stdout,
                stderr: &stderr
            )
            highest = max(highest, code)
            if stops { return highest }
        }
        return highest
    }

    /// Reports an event line that did not load: `line N: Error: ...` on
    /// `stderr`, and with `--json` an error record on `stdout`, so the event
    /// still prints one line.
    private static func reportBadLine(
        _ error: ContextLoadError,
        line: Int,
        invocation: Invocation,
        stdout: inout some TextOutputStream,
        stderr: inout some TextOutputStream
    ) {
        print("line \(line): " + ExitCode.message(for: error), to: &stderr)
        if invocation.json {
            let record = JSONOutput.errorLine(
                for: invocation.questions, message: ExitCode.reason(for: error)
            )
            print(record, terminator: "", to: &stdout)
        }
    }

    /// The code a decided run returns. One yes/no question answers with its
    /// exit code as well, like grep: 0 when its printed answer is the yes
    /// value, 1 otherwise. Every other run returns 0.
    private static func exitCode(for printed: [String?], questions: [Question]) -> Int32 {
        guard questions.count == 1, case .verdict(let yes, _) = questions[0].kind,
              let answer = printed.first
        else {
            return ExitCode.decided
        }
        return answer == yes.id ? ExitCode.decided : ExitCode.no
    }

    /// Prints a usage error and the usage text to `stderr`.
    private static func report(_ error: UsageError, to stderr: inout some TextOutputStream) {
        print(ExitCode.message(for: error), to: &stderr)
        print("", to: &stderr)
        print(usage, to: &stderr)
    }

    /// Writes what `--set-config` names into a config file and gives the
    /// exit code. A key from standard input is read first. Success prints
    /// nothing. Every failure prints one line to `stderr` and leaves the
    /// file as it was.
    private static func setConfig(
        _ request: SetConfig,
        environment: [String: String],
        currentDirectory: String?,
        standardInput: any StandardInputReading,
        stderr: inout some TextOutputStream
    ) -> Int32 {
        var request = request
        if request.apiKey == .standardInput {
            do {
                request.apiKey = .value(try readAPIKey(from: standardInput, stderr: &stderr))
            } catch {
                print(ExitCode.message(for: error), to: &stderr)
                return ExitCode.setup
            }
        }
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
        // A `.standardInput` key never reaches here: `setConfig` reads it
        // into `.value` first.
        if case .value(let apiKey)? = request.apiKey {
            pairs.append((ModelConfiguration.apiKeyVariable, apiKey))
        }
        return pairs
    }

    /// Reads the key `--api-key -` asks for: one line of standard input,
    /// trimmed. At a terminal it prompts on `stderr` first, with no line
    /// ending, and ends the line after the read, because echo off swallowed
    /// the user's Enter; the line ends even when the read throws, so the
    /// error starts on its own line. From a pipe it prints nothing, so a
    /// script's stderr stays clean. An empty line, or end of file before
    /// any line, is `.empty`.
    private static func readAPIKey(
        from standardInput: any StandardInputReading,
        stderr: inout some TextOutputStream
    ) throws(APIKeyError) -> String {
        let prompts = standardInput.isTerminal
        if prompts { print("API key: ", terminator: "", to: &stderr) }
        defer { if prompts { print("", to: &stderr) } }
        let line: String?
        do {
            line = try standardInput.readSecretLine()
        } catch {
            switch error {
            case .unreadable: throw .unreadable
            case .notUTF8: throw .notUTF8
            }
        }
        let key = line?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw .empty }
        return key
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

    /// The context with every `.file` source read to `.text`. `.text` and
    /// `.standardInput` stay as they are. A stream calls it once, so it
    /// reads no file twice. Throws `.unreadableFile` when a file does not
    /// read.
    static func readingFiles(in context: Context) throws(ContextLoadError) -> Context {
        func read(_ source: ContextSource) throws(ContextLoadError) -> ContextSource {
            guard case .file(let path) = source else { return source }
            return .text(try readContextFile(path))
        }
        switch context {
        case .single(let source, let format):
            return .single(try read(source), format)
        case .named(let contexts):
            var named: [NamedContext] = []
            for context in contexts {
                let source = try read(context.source)
                named.append(
                    NamedContext(name: context.name, source: source, format: context.format)
                )
            }
            return .named(named)
        }
    }

    /// Reads the run's context into the state the model sees. One context is
    /// its text, or its parsed value with `.json`. Named contexts are one
    /// object, each field the text or parsed value of the context of that
    /// name, read in command-line order. Throws when a file or standard input
    /// does not read, or when a `.json` context's text is not valid JSON.
    private static func loadState(
        _ context: Context,
        standardInput: () throws(ConfigReadError) -> String
    ) throws(ContextLoadError) -> State {
        switch context {
        case .single(let source, let format):
            let text = try loadContext(source, standardInput: standardInput)
            return try state(of: text, as: format, named: nil)
        case .named(let contexts):
            // Assignment, not `Dictionary(uniqueKeysWithValues:)`, which traps
            // on a repeated name. The parser keeps names unique, but
            // `Invocation` is public, so the last one wins instead.
            var fields: [String: State] = [:]
            for context in contexts {
                let text = try loadContext(context.source, standardInput: standardInput)
                fields[context.name] = try state(of: text, as: context.format, named: context.name)
            }
            return .object(fields)
        }
    }

    /// The state one context's text gives: the text itself for `.text`, or
    /// its parsed value for `.json`. A leading BOM is dropped before the
    /// parse, as a question file's is. Throws `.notJSON` when the text is not
    /// valid JSON; empty text is not. The message carries none of
    /// Foundation's detail, which differs by platform. `name` is the
    /// context's name, or nil for an unnamed one.
    private static func state(
        of text: String,
        as format: ContextFormat,
        named name: String?
    ) throws(ContextLoadError) -> State {
        switch format {
        case .text:
            return .text(text)
        case .json:
            var scalars = text.unicodeScalars[...]
            if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
            let data = Data(String(scalars).utf8)
            guard let state = try? JSONDecoder().decode(State.self, from: data) else {
                throw .notJSON(name: name)
            }
            return state
        }
    }

    /// Reads the context. `.text` is the text itself; `.file` is read as
    /// UTF-8, and `.standardInput` through `standardInput`. Throws when the
    /// file or standard input does not read.
    private static func loadContext(
        _ source: ContextSource,
        standardInput: () throws(ConfigReadError) -> String
    ) throws(ContextLoadError) -> String {
        switch source {
        case .text(let text):
            return text
        case .file(let path):
            return try readContextFile(path)
        case .standardInput:
            do {
                return try standardInput()
            } catch {
                switch error {
                case .unreadable: throw .unreadableInput
                case .notUTF8: throw .inputNotUTF8
                }
            }
        }
    }

    /// Reads a context file as UTF-8. Throws `.unreadableFile` with the
    /// system's reason when it does not read.
    private static func readContextFile(_ path: String) throws(ContextLoadError) -> String {
        do {
            return try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw .unreadableFile(path: path, reason: error.localizedDescription)
        }
    }
}

/// Why a context did not load: its file or standard input did not read, or
/// a `.json` context's text is not valid JSON.
enum ContextLoadError: Error, Equatable {
    /// A context file that does not read, with the path and the system's reason.
    case unreadableFile(path: String, reason: String)
    /// Standard input that does not read.
    case unreadableInput
    /// Standard input that is not UTF-8.
    case inputNotUTF8
    /// An event line that is not UTF-8, under `--each`.
    case lineNotUTF8
    /// A `.json` context whose text is not valid JSON. `name` is nil for an
    /// unnamed context.
    case notJSON(name: String?)

    /// The message, after `Error: `.
    var message: String {
        switch self {
        case .unreadableFile(let path, let reason):
            "cannot read context file \"\(path)\": \(reason)"
        case .unreadableInput: "cannot read standard input"
        case .inputNotUTF8: "standard input is not valid UTF-8"
        case .lineNotUTF8: "the line is not valid UTF-8"
        case .notJSON(let name):
            (name.map { "context \"\($0)\"" } ?? "the context") + " is not valid JSON"
        }
    }
}

/// Why `--api-key -` gave no key: standard input held none, did not
/// read, or was not UTF-8.
enum APIKeyError: Error, Equatable {
    /// An empty line, or end of file before any line.
    case empty
    /// Standard input that does not read.
    case unreadable
    /// A line that is not UTF-8.
    case notUTF8

    /// The message, after `Error: `.
    var message: String {
        switch self {
        case .empty: "standard input holds no API key"
        case .unreadable: "cannot read standard input"
        case .notUTF8: "standard input is not valid UTF-8"
        }
    }
}
