/// What the command line asks for: help, the version, a config write, or
/// one run.
public enum ParseResult: Equatable, Sendable {
    case help
    /// `--version`. `alone` is false when any other argument came with it,
    /// which is a usage error that `Decide.run` reports after the version.
    case version(alone: Bool)
    /// `--set-config`, and the settings it writes.
    case setConfig(SetConfig)
    case run(Invocation)
}

/// What `--set-config` writes, and where.
///
/// At least one of `model` and `apiKey` is set. The values are as the user
/// typed them: the model is trimmed when it is read back, and the key is
/// written as given.
public struct SetConfig: Equatable, Sendable {
    /// The value for DECIDE_MODEL, or nil without `--model`.
    public var model: String?
    /// The value for DECIDE_MODEL_API_KEY, or nil without `--api-key`.
    /// Never set with `project`: the trust rule keeps a key out of a
    /// project file.
    public var apiKey: String?
    /// Write `./.decide/config` instead of the home config, from
    /// `--project`.
    public var project: Bool

    public init(model: String?, apiKey: String?, project: Bool = false) {
        self.model = model
        self.apiKey = apiKey
        self.project = project
    }
}

/// Turns the argument list (after the program name) into an `Invocation`.
/// Pure: no file or network I/O.
public enum CommandLineParser {
    /// Parses the arguments.
    ///
    /// A bare token starts a question. Each later `--option` or `--level`
    /// joins that question and sets its kind. A question with neither is a
    /// yes/no question; `--yes` and `--no` set what it prints.
    /// `--min-confidence` after a question sets the confidence its answer
    /// needs. `--quiet` or `-q` keeps the one yes/no question's answer off
    /// stdout. `--context` is optional; without it the questions run with no
    /// state. A `--context` whose value starts with a name and `=` is a named
    /// context, and the model sees every named context as one field of one
    /// object; a name that is not an identifier is an error, not text. A
    /// line with more than one `--context` must name every one.
    /// `--version` anywhere returns `.version(alone:)`, alone or not.
    /// Without it, `--help` or `-h` anywhere returns `.help`. `--set-config`
    /// after those two takes the line for itself: `--model`, `--api-key`, and
    /// `--project` join it, and any other token is an error. Anything the
    /// tool cannot run throws a `UsageError` that names the problem.
    public static func parse(_ arguments: [String]) throws(UsageError) -> ParseResult {
        guard !arguments.isEmpty else { throw UsageError("no arguments given") }
        if arguments.contains("--version") { return .version(alone: arguments.count == 1) }
        if arguments.contains(where: { $0 == "--help" || $0 == "-h" }) { return .help }
        if arguments.contains("--set-config") { return .setConfig(try parseSetConfig(arguments)) }

        var contexts: [ContextEntry] = []
        var questions: [QuestionBuilder] = []
        var quiet = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            index += 1

            if token == "--quiet" || token == "-q" {
                guard !quiet else { throw UsageError("--quiet was given twice") }
                quiet = true
                continue
            }

            if let value = try flagValue(of: "--context", token: token, arguments: arguments, index: &index) {
                contexts.append(try contextEntry(from: value))
                continue
            }

            if let value = try flagValue(of: "--option", token: token, arguments: arguments, index: &index) {
                try add(value, as: .option, to: &questions)
                continue
            }

            if let value = try flagValue(of: "--level", token: token, arguments: arguments, index: &index) {
                try add(value, as: .level, to: &questions)
                continue
            }

            if let value = try flagValue(of: "--yes", token: token, arguments: arguments, index: &index) {
                try add(value, as: .yes, to: &questions)
                continue
            }

            if let value = try flagValue(of: "--no", token: token, arguments: arguments, index: &index) {
                try add(value, as: .no, to: &questions)
                continue
            }

            if let value = try flagValue(
                of: "--min-confidence", token: token, arguments: arguments, index: &index
            ) {
                try setMinimumConfidence(value, to: &questions)
                continue
            }

            if let flag = setConfigFlag(token) {
                throw UsageError("\(flag) needs --set-config")
            }

            if token.hasPrefix("-") { throw UsageError("unknown flag: \(token)") }

            guard !token.isEmpty else { throw UsageError("question \(questions.count + 1) is empty") }
            questions.append(QuestionBuilder(instructions: token))
        }

        guard !questions.isEmpty else { throw UsageError("no question given") }

        var finished: [Question] = []
        for (offset, builder) in questions.enumerated() {
            let question = try builder.question(number: offset + 1)
            finished.append(question)
        }

        let context = try Self.context(from: contexts)

        if quiet {
            guard finished.count == 1, case .verdict = finished[0].kind else {
                throw UsageError("--quiet needs exactly one yes/no question")
            }
        }

        return .run(Invocation(context: context, questions: finished, quiet: quiet))
    }

    /// Parses a line that holds `--set-config`.
    ///
    /// The flag takes `--model`, `--api-key`, and `--project`, each once,
    /// and nothing else. `--model` and `--api-key` take `--flag value` or
    /// `--flag=value`. The line must set at least one of the two, and a key
    /// may not go to a project file.
    private static func parseSetConfig(_ arguments: [String]) throws(UsageError) -> SetConfig {
        var model: String?
        var apiKey: String?
        var project = false
        var seen = false
        var index = 0

        while index < arguments.count {
            let token = arguments[index]
            index += 1

            if token == "--set-config" {
                guard !seen else { throw UsageError("--set-config was given twice") }
                seen = true
                continue
            }

            if token == "--project" {
                guard !project else { throw UsageError("--project was given twice") }
                project = true
                continue
            }

            if let value = try flagValue(of: "--model", token: token, arguments: arguments, index: &index) {
                guard model == nil else { throw UsageError("--model was given twice") }
                model = try setting(value, of: "--model")
                continue
            }

            if let value = try flagValue(of: "--api-key", token: token, arguments: arguments, index: &index) {
                guard apiKey == nil else { throw UsageError("--api-key was given twice") }
                apiKey = try setting(value, of: "--api-key")
                continue
            }

            throw UsageError("--set-config runs alone")
        }

        guard model != nil || apiKey != nil else {
            throw UsageError("--set-config needs --model or --api-key")
        }
        guard apiKey == nil || !project else {
            throw UsageError("--api-key is allowed only in the home config, not in a project's")
        }
        return SetConfig(model: model, apiKey: apiKey, project: project)
    }

    /// The value of a `--set-config` flag. A value that is empty or only
    /// whitespace sets nothing, so it is an error. Anything else goes on as
    /// the user typed it.
    private static func setting(_ value: String, of flag: String) throws(UsageError) -> String {
        guard !value.allSatisfy(\.isWhitespace) else { throw UsageError("\(flag) is empty") }
        return value
    }

    /// The `--set-config` flag a token names, or nil for any other token.
    /// `--model=x` and `--api-key=x` match too, so both forms of a value
    /// report the same problem.
    private static func setConfigFlag(_ token: String) -> String? {
        if token == "--project" { return "--project" }
        for flag in ["--model", "--api-key"] where token == flag || token.hasPrefix(flag + "=") {
            return flag
        }
        return nil
    }

    /// One `--context` value as the parser reads it, before the line's values
    /// are checked together.
    private enum ContextEntry {
        case unnamed(ContextSource)
        case named(NamedContext)
    }

    /// One question as the parser builds it. `flag` is the first kind flag
    /// under it, and stays `nil` until one arrives. `yes` and `no` hold the
    /// two sides of a yes/no question in any order, so a repeat of either flag
    /// is its own error. `minimumConfidence` is the bar `--min-confidence`
    /// sets, on a question of any kind.
    private struct QuestionBuilder {
        let instructions: String
        var flag: KindFlag?
        var values: [Option] = []
        var yes: Option?
        var no: Option?
        var minimumConfidence: Double?

        /// How a message names this question: its number and its text.
        func name(_ number: Int) -> String {
            "question \(number) (\"\(instructions)\")"
        }

        /// The finished question. A question with no kind flag is a yes/no
        /// question. Throws when its flags do not make one.
        func question(number: Int) throws(UsageError) -> Question {
            guard let flag else { return try verdict(number: number) }
            var seen: Set<String> = []
            for value in values {
                guard seen.insert(value.id).inserted else {
                    throw UsageError("\(name(number)) repeats the \(flag.noun) \"\(value.id)\"")
                }
            }
            switch flag {
            case .option:
                return Question(
                    instructions: instructions,
                    kind: .choice(values),
                    minimumConfidence: minimumConfidence
                )
            case .level:
                guard values.count >= 2 else {
                    throw UsageError("\(name(number)) needs at least two --level")
                }
                return Question(
                    instructions: instructions,
                    kind: .rating(values),
                    minimumConfidence: minimumConfidence
                )
            case .yes, .no:
                return try verdict(number: number)
            }
        }

        /// The finished yes/no question. A side the user left out takes its
        /// default value. Throws when the two sides print the same value,
        /// which would make the two probabilities one.
        private func verdict(number: Int) throws(UsageError) -> Question {
            let yesSide = yes ?? Option(id: "yes")
            let noSide = no ?? Option(id: "no")
            guard yesSide.id != noSide.id else {
                throw UsageError("\(name(number)) uses the same value for --yes and --no")
            }
            return Question(
                instructions: instructions,
                kind: .verdict(yes: yesSide, no: noSide),
                minimumConfidence: minimumConfidence
            )
        }
    }

    /// A flag that belongs to a question. `--option` makes a choice,
    /// `--level` makes a rating, and `--yes` or `--no` decorates a yes/no
    /// question.
    private enum KindFlag: String {
        case option = "--option"
        case level = "--level"
        case yes = "--yes"
        case no = "--no"

        /// The kind a flag makes. The mixed-kinds check compares groups, so
        /// `--yes` and `--no` go on one question.
        enum Group {
            case choice
            case rating
            case verdict
        }

        /// The kind this flag makes.
        var group: Group {
            switch self {
            case .option: .choice
            case .level: .rating
            case .yes, .no: .verdict
            }
        }

        /// What the flag adds to a question, for a message about one repeated
        /// value. A yes/no question holds one value per side, so a repeat of
        /// `--yes` or `--no` is its own error and never reads this.
        var noun: String {
            switch self {
            case .option: "option"
            case .level: "level"
            case .yes, .no: "value"
            }
        }

        /// What an empty value, or one with nothing before the `=`, reports.
        /// The wording differs by flag, so the whole sentence lives here.
        var missingID: String {
            switch self {
            case .option: "an --option has no id"
            case .level: "a --level has no id"
            case .yes: "a --yes has no value"
            case .no: "a --no has no value"
            }
        }
    }

    /// Adds an option, a level, or a yes or no side to the last question. The
    /// first kind flag fixes the kind, so a flag of another kind is an error.
    /// Each question takes `--yes` once and `--no` once.
    private static func add(
        _ value: String,
        as flag: KindFlag,
        to questions: inout [QuestionBuilder]
    ) throws(UsageError) {
        guard let last = questions.indices.last else {
            throw UsageError("\(flag.rawValue) before any question")
        }
        if let existing = questions[last].flag, existing.group != flag.group {
            throw UsageError(
                "\(questions[last].name(last + 1)) mixes \(existing.rawValue) and \(flag.rawValue)"
            )
        }
        let parsed = try option(from: value, as: flag)
        switch flag {
        case .option, .level:
            questions[last].values.append(parsed)
        case .yes:
            guard questions[last].yes == nil else {
                throw UsageError("\(questions[last].name(last + 1)) repeats --yes")
            }
            questions[last].yes = parsed
        case .no:
            guard questions[last].no == nil else {
                throw UsageError("\(questions[last].name(last + 1)) repeats --no")
            }
            questions[last].no = parsed
        }
        if questions[last].flag == nil { questions[last].flag = flag }
    }

    /// Sets the confidence bar on the last question. Every kind takes the
    /// flag, and each question takes it once. The value must be a number from
    /// 0 to 1, so `nan` and `inf` are errors.
    private static func setMinimumConfidence(
        _ value: String,
        to questions: inout [QuestionBuilder]
    ) throws(UsageError) {
        guard let last = questions.indices.last else {
            throw UsageError("--min-confidence before any question")
        }
        guard questions[last].minimumConfidence == nil else {
            throw UsageError("\(questions[last].name(last + 1)) repeats --min-confidence")
        }
        guard let bar = Double(value), bar.isFinite, (0...1).contains(bar) else {
            throw UsageError("--min-confidence needs a number from 0 to 1, got \"\(value)\"")
        }
        questions[last].minimumConfidence = bar
    }

    /// Reads the value of a flag that takes one. Returns `nil` when the token
    /// is some other flag or a bare word. Accepts `--flag value` and
    /// `--flag=value`, and steps the index past a value it consumes.
    private static func flagValue(
        of flag: String,
        token: String,
        arguments: [String],
        index: inout Int
    ) throws(UsageError) -> String? {
        if token == flag {
            guard index < arguments.count else { throw UsageError("\(flag) needs a value") }
            let value = arguments[index]
            index += 1
            return value
        }
        if token.hasPrefix(flag + "=") { return String(token.dropFirst(flag.count + 1)) }
        return nil
    }

    /// Reads one `--context` value. The text before the first `=` is a name
    /// attempt when it is non-empty and holds no whitespace: a valid name makes
    /// a named context, and an invalid one is an error. Any other value is
    /// unnamed: the text itself, or a file when it starts with `@`.
    private static func contextEntry(from value: String) throws(UsageError) -> ContextEntry {
        guard let separator = value.firstIndex(of: "=") else {
            return .unnamed(try contextSource(from: value, as: "--context "))
        }
        let name = String(value[value.startIndex..<separator])
        guard !name.isEmpty, !name.contains(where: \.isWhitespace) else {
            return .unnamed(try contextSource(from: value, as: "--context "))
        }
        guard isName(name) else {
            throw UsageError(
                "--context name \"\(name)\" is not valid: a letter or _ then letters, digits, or _"
            )
        }
        let rest = String(value[value.index(after: separator)...])
        guard !rest.isEmpty else { throw UsageError("--context \(name)= has no value") }
        let source = try contextSource(from: rest, as: "--context \(name)=")
        return .named(NamedContext(name: name, source: source))
    }

    /// Whether the text is a name: ASCII, a letter or `_` first, then letters,
    /// digits, or `_`.
    private static func isName(_ text: String) -> Bool {
        guard let first = text.first, first.isASCII, first.isLetter || first == "_" else {
            return false
        }
        return text.dropFirst().allSatisfy { character in
            character.isASCII && (character.isLetter || character.isNumber || character == "_")
        }
    }

    /// Reads the text or path of a `--context` value. A leading `@` names a
    /// file. Anything else is the text itself, and a later `@` stays literal.
    /// `prefix` is what the names-no-file message quotes before the `@`:
    /// `--context ` for an unnamed value, `--context ticket=` for a named one.
    private static func contextSource(
        from value: String,
        as prefix: String
    ) throws(UsageError) -> ContextSource {
        guard value.hasPrefix("@") else { return .text(value) }
        let path = String(value.dropFirst())
        guard !path.isEmpty else { throw UsageError("\(prefix)@ names no file") }
        return .file(path)
    }

    /// The line's context from its `--context` values, in order. None is nil,
    /// one unnamed value is `.single`, and named values are `.named`. With more
    /// than one value every one needs a name, and no name may repeat. The mix
    /// check runs first, so a line with both problems reports the mix.
    private static func context(from entries: [ContextEntry]) throws(UsageError) -> Context? {
        guard !entries.isEmpty else { return nil }
        if entries.count == 1, case .unnamed(let source) = entries[0] { return .single(source) }
        var named: [NamedContext] = []
        for entry in entries {
            guard case .named(let context) = entry else {
                throw UsageError(
                    """
                    every --context needs a name when there is more than one, \
                    like --context ticket=@ticket.txt
                    """
                )
            }
            named.append(context)
        }
        var seen: Set<String> = []
        for context in named {
            guard seen.insert(context.name).inserted else {
                throw UsageError("--context names \"\(context.name)\" twice")
            }
        }
        return .named(named)
    }

    /// Reads an `--option`, `--level`, `--yes`, or `--no` value. The first
    /// `=` splits the id from the description. An empty description counts as
    /// none.
    private static func option(from value: String, as flag: KindFlag) throws(UsageError) -> Option {
        guard let separator = value.firstIndex(of: "=") else {
            guard !value.isEmpty else { throw UsageError(flag.missingID) }
            return Option(id: value)
        }
        let id = String(value[value.startIndex..<separator])
        guard !id.isEmpty else { throw UsageError(flag.missingID) }
        let description = String(value[value.index(after: separator)...])
        return Option(id: id, description: description.isEmpty ? nil : description)
    }
}
