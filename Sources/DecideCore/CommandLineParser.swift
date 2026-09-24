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
    /// needs. `--fallback` after a question names what it prints when its
    /// answer is below its bar or the run has a remote error; on a yes/no
    /// question it is the yes or no value. `--name` after a question gives it
    /// a name, an identifier that is unique in the run; its line prints as
    /// `name=answer`. `--stats` after a question adds its numbers to its
    /// line, and `--distribution` adds those and one field per option, level,
    /// or side; neither goes with `--quiet`. An `--option`, `--level`,
    /// `--yes`, or `--no` id holds no tab or newline: a tab separates the
    /// fields those two flags add.
    /// `--quiet` or `-q` keeps the one yes/no question's answer off stdout.
    /// `--json` prints the answers as one JSON object, and does not go with
    /// `--quiet`. `--context` is optional; without it the questions run
    /// with no state. A `--context` whose value starts with a name and `=` is
    /// a named context, and the model sees every named context as one field
    /// of one object; a name that is not an identifier is an error, not text.
    /// A line with more than one `--context` must name every one. `--model`
    /// and `--api-key` set the model and key for this run, over the
    /// environment and every config file. `--version` anywhere returns
    /// `.version(alone:)`, alone or not. Without it, `--help` or `-h`
    /// anywhere returns `.help`. `--set-config` after those two takes the
    /// line for itself: `--model`, `--api-key`, and `--project` join it, and
    /// any other token is an error. `--questions` is an error: the caller
    /// expands it first, so the parser reads no file. Anything the tool
    /// cannot run throws a `UsageError` that names the problem.
    public static func parse(_ arguments: [String]) throws(UsageError) -> ParseResult {
        guard !arguments.isEmpty else { throw UsageError("no arguments given") }
        return try parse(items: arguments.map(QuestionFile.Item.token))
    }

    /// Parses the items `QuestionFile.expanding(_:read:)` gives, as
    /// `parse(_:)` parses arguments. No items is no question: the line may
    /// hold only an empty question file.
    ///
    /// A `.questions` item puts its finished questions at its place among the
    /// questions the line builds, and they count in every question number. A
    /// question flag after it, before the next question, belongs to no
    /// question and is an error.
    public static func parse(items: [QuestionFile.Item]) throws(UsageError) -> ParseResult {
        let tokens = items.compactMap { item -> String? in
            guard case .token(let token) = item else { return nil }
            return token
        }
        if takesTheLine(tokens) {
            if tokens.contains("--version") { return .version(alone: items.count == 1) }
            if tokens.contains(where: { $0 == "--help" || $0 == "-h" }) { return .help }
            guard tokens.count == items.count else { throw UsageError("--set-config runs alone") }
            return .setConfig(try parseSetConfig(tokens))
        }

        var contexts: [ContextEntry] = []
        var entries: [Entry] = []
        var quiet = false
        var json = false
        var model: String?
        var apiKey: String?
        var start = 0

        while start < items.count {
            if case .questions(let finished) = items[start] {
                entries.append(contentsOf: finished.map(Entry.done))
                start += 1
                continue
            }
            // The tokens up to the next `.questions` item. A flag's value
            // comes from these, so it never reaches past that item.
            var arguments: [String] = []
            while start < items.count, case .token(let token) = items[start] {
                arguments.append(token)
                start += 1
            }
            var index = 0

            while index < arguments.count {
                let token = arguments[index]
                index += 1

                if token == "--quiet" || token == "-q" {
                    guard !quiet else { throw UsageError("--quiet was given twice") }
                    quiet = true
                    continue
                }

                if token == "--json" {
                    guard !json else { throw UsageError("--json was given twice") }
                    json = true
                    continue
                }

                if let value = try flagValue(of: "--context", token: token, arguments: arguments, index: &index) {
                    contexts.append(try contextEntry(from: value))
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

                if let value = try flagValue(of: "--option", token: token, arguments: arguments, index: &index) {
                    try add(value, as: .option, to: &entries)
                    continue
                }

                if let value = try flagValue(of: "--level", token: token, arguments: arguments, index: &index) {
                    try add(value, as: .level, to: &entries)
                    continue
                }

                if let value = try flagValue(of: "--yes", token: token, arguments: arguments, index: &index) {
                    try add(value, as: .yes, to: &entries)
                    continue
                }

                if let value = try flagValue(of: "--no", token: token, arguments: arguments, index: &index) {
                    try add(value, as: .no, to: &entries)
                    continue
                }

                if let value = try flagValue(
                    of: "--min-confidence", token: token, arguments: arguments, index: &index
                ) {
                    try setMinimumConfidence(value, to: &entries)
                    continue
                }

                if let value = try flagValue(
                    of: "--fallback", token: token, arguments: arguments, index: &index
                ) {
                    try setFallback(value, to: &entries)
                    continue
                }

                if let value = try flagValue(of: "--name", token: token, arguments: arguments, index: &index) {
                    try setName(value, to: &entries)
                    continue
                }

                if let flag = DetailFlag(rawValue: token) {
                    try setDetail(flag, to: &entries)
                    continue
                }

                if try flagValue(
                    of: "--questions", token: token, arguments: arguments, index: &index
                ) != nil {
                    throw UsageError("--questions was not expanded")
                }

                if token == "--project" { throw UsageError("--project needs --set-config") }

                if token.hasPrefix("-") { throw UsageError("unknown flag: \(token)") }

                guard !token.isEmpty else {
                    throw UsageError("question \(entries.count + 1) is empty")
                }
                entries.append(.building(QuestionBuilder(instructions: token)))
            }
        }

        guard !entries.isEmpty else { throw UsageError("no question given") }

        var finished: [Question] = []
        for (offset, entry) in entries.enumerated() {
            switch entry {
            case .building(let builder):
                finished.append(try builder.question(number: offset + 1))
            case .done(let question):
                finished.append(question)
            }
        }

        try checkUniqueNames(finished)

        let context = try Self.context(from: contexts)

        if json && quiet { throw UsageError("--json does not go with --quiet") }

        if quiet, let detailed = finished.first(where: { $0.detail != .answer }) {
            throw UsageError(
                detailed.detail == .distribution
                    ? "--distribution does not go with --quiet"
                    : "--stats does not go with --quiet"
            )
        }

        if quiet {
            guard finished.count == 1, case .verdict = finished[0].kind else {
                throw UsageError("--quiet needs exactly one yes/no question")
            }
        }

        return .run(
            Invocation(
                context: context,
                questions: finished,
                quiet: quiet,
                json: json,
                model: model,
                apiKey: apiKey
            )
        )
    }

    /// Whether a flag on the line takes the whole line: `--version`,
    /// `--help`, `-h`, or `--set-config`. The parser answers such a line
    /// before it reads any question, and the expansion reads no file for it.
    static func takesTheLine(_ arguments: [String]) -> Bool {
        arguments.contains { ["--version", "--help", "-h", "--set-config"].contains($0) }
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

    /// The value of a `--model` or `--api-key` flag. A value that is empty or
    /// only whitespace sets nothing, so it is an error. Anything else goes on
    /// as the user typed it.
    private static func setting(_ value: String, of flag: String) throws(UsageError) -> String {
        guard !value.allSatisfy(\.isWhitespace) else { throw UsageError("\(flag) is empty") }
        return value
    }

    /// One `--context` value as the parser reads it, before the line's values
    /// are checked together.
    private enum ContextEntry {
        case unnamed(ContextSource)
        case named(NamedContext)
    }

    /// One question on the line, in line order: one the parser still builds
    /// from the flags after it, or one a `.questions` item gave finished.
    private enum Entry {
        case building(QuestionBuilder)
        case done(Question)
    }

    /// One question as the parser builds it. `flag` is the first kind flag
    /// under it, and stays `nil` until one arrives. `yes` and `no` hold the
    /// two sides of a yes/no question in any order, so a repeat of either flag
    /// is its own error. `minimumConfidence` is the bar `--min-confidence`
    /// sets, and `fallback` the value `--fallback` sets, on a question of any
    /// kind. `name` is the identifier `--name` gives it, or nil. `stats` and
    /// `distribution` are the two flags that add to its line.
    private struct QuestionBuilder {
        let instructions: String
        var flag: KindFlag?
        var values: [Option] = []
        var yes: Option?
        var no: Option?
        var minimumConfidence: Double?
        var fallback: String?
        var name: String?
        var stats = false
        var distribution = false

        /// How a message names this question: its number and its text.
        func label(_ number: Int) -> String {
            "question \(number) (\"\(instructions)\")"
        }

        /// What the question's line shows. `--distribution` wins over
        /// `--stats`, because it holds the stats.
        var detail: Question.Detail {
            distribution ? .distribution : (stats ? .stats : .answer)
        }

        /// The finished question. A question with no kind flag is a yes/no
        /// question. Throws when its flags do not make one.
        func question(number: Int) throws(UsageError) -> Question {
            guard let flag else { return try verdict(number: number) }
            var seen: Set<String> = []
            for value in values {
                guard seen.insert(value.id).inserted else {
                    throw UsageError("\(label(number)) repeats the \(flag.noun) \"\(value.id)\"")
                }
            }
            switch flag {
            case .option:
                return Question(
                    instructions: instructions,
                    kind: .choice(values),
                    minimumConfidence: minimumConfidence,
                    fallback: fallback,
                    name: name,
                    detail: detail
                )
            case .level:
                guard values.count >= 2 else {
                    throw UsageError("\(label(number)) needs at least two --level")
                }
                return Question(
                    instructions: instructions,
                    kind: .rating(values),
                    minimumConfidence: minimumConfidence,
                    fallback: fallback,
                    name: name,
                    detail: detail
                )
            case .yes, .no:
                return try verdict(number: number)
            }
        }

        /// The finished yes/no question. A side the user left out takes its
        /// default value. Throws when the two sides print the same value,
        /// which would make the two probabilities one, and when the fallback
        /// is neither side's value.
        private func verdict(number: Int) throws(UsageError) -> Question {
            let yesSide = yes ?? Option(id: "yes")
            let noSide = no ?? Option(id: "no")
            guard yesSide.id != noSide.id else {
                throw UsageError("\(label(number)) uses the same value for --yes and --no")
            }
            if let fallback, fallback != yesSide.id, fallback != noSide.id {
                throw UsageError(
                    "\(label(number)) has a fallback \"\(fallback)\" that is not its --yes or --no value"
                )
            }
            return Question(
                instructions: instructions,
                kind: .verdict(yes: yesSide, no: noSide),
                minimumConfidence: minimumConfidence,
                fallback: fallback,
                name: name,
                detail: detail
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

        /// What an id holding a tab or a newline reports. The wording
        /// differs by flag, as `missingID`'s does.
        var idHasWhitespace: String {
            switch self {
            case .option: "an --option id holds a tab or newline"
            case .level: "a --level id holds a tab or newline"
            case .yes: "a --yes value holds a tab or newline"
            case .no: "a --no value holds a tab or newline"
            }
        }
    }

    /// A flag that adds to a question's line. `--stats` adds the answer's
    /// numbers, and `--distribution` adds those and the probability of every
    /// option, level, or side.
    private enum DetailFlag: String {
        case stats = "--stats"
        case distribution = "--distribution"

        /// The builder field this flag sets.
        var field: WritableKeyPath<QuestionBuilder, Bool> {
            switch self {
            case .stats: \.stats
            case .distribution: \.distribution
            }
        }
    }

    /// The last question on the line, which a question flag joins, and its
    /// index. Throws when there is no question yet, or when the last one came
    /// finished from a `.questions` item.
    private static func lastBuilder(
        _ entries: [Entry],
        for flag: String
    ) throws(UsageError) -> (index: Int, builder: QuestionBuilder) {
        guard let last = entries.indices.last else {
            throw UsageError("\(flag) before any question")
        }
        guard case .building(let builder) = entries[last] else {
            throw UsageError("\(flag) after --questions belongs to no question")
        }
        return (last, builder)
    }

    /// Adds an option, a level, or a yes or no side to the last question. The
    /// first kind flag fixes the kind, so a flag of another kind is an error.
    /// Each question takes `--yes` once and `--no` once.
    private static func add(
        _ value: String,
        as flag: KindFlag,
        to entries: inout [Entry]
    ) throws(UsageError) {
        var (last, builder) = try lastBuilder(entries, for: flag.rawValue)
        if let existing = builder.flag, existing.group != flag.group {
            throw UsageError(
                "\(builder.label(last + 1)) mixes \(existing.rawValue) and \(flag.rawValue)"
            )
        }
        let parsed = try option(from: value, as: flag)
        switch flag {
        case .option, .level:
            builder.values.append(parsed)
        case .yes:
            guard builder.yes == nil else {
                throw UsageError("\(builder.label(last + 1)) repeats --yes")
            }
            builder.yes = parsed
        case .no:
            guard builder.no == nil else {
                throw UsageError("\(builder.label(last + 1)) repeats --no")
            }
            builder.no = parsed
        }
        if builder.flag == nil { builder.flag = flag }
        entries[last] = .building(builder)
    }

    /// Sets the confidence bar on the last question. Every kind takes the
    /// flag, and each question takes it once. The value must be a number from
    /// 0 to 1, so `nan` and `inf` are errors.
    private static func setMinimumConfidence(
        _ value: String,
        to entries: inout [Entry]
    ) throws(UsageError) {
        var (last, builder) = try lastBuilder(entries, for: "--min-confidence")
        guard builder.minimumConfidence == nil else {
            throw UsageError("\(builder.label(last + 1)) repeats --min-confidence")
        }
        guard let bar = Double(value), bar.isFinite, (0...1).contains(bar) else {
            throw UsageError("--min-confidence needs a number from 0 to 1, got \"\(value)\"")
        }
        builder.minimumConfidence = bar
        entries[last] = .building(builder)
    }

    /// Sets the fallback on the last question. Every kind takes the flag, and
    /// each question takes it once. The value is not empty and holds no tab,
    /// line feed, or carriage return, the same rule as an id. A yes/no
    /// question checks it against its sides when it is built, because
    /// `--yes` and `--no` may come after it.
    private static func setFallback(
        _ value: String,
        to entries: inout [Entry]
    ) throws(UsageError) {
        var (last, builder) = try lastBuilder(entries, for: "--fallback")
        guard builder.fallback == nil else {
            throw UsageError("\(builder.label(last + 1)) repeats --fallback")
        }
        guard !value.isEmpty else { throw UsageError("a --fallback has no value") }
        let forbidden: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
        guard !value.unicodeScalars.contains(where: forbidden.contains) else {
            throw UsageError("a --fallback value holds a tab or newline")
        }
        builder.fallback = value
        entries[last] = .building(builder)
    }

    /// Names the last question. Every kind takes the flag, and each question
    /// takes it once. The name is an identifier; the run-wide uniqueness
    /// check comes after every question is built.
    private static func setName(
        _ value: String,
        to entries: inout [Entry]
    ) throws(UsageError) {
        var (last, builder) = try lastBuilder(entries, for: "--name")
        guard builder.name == nil else {
            throw UsageError("\(builder.label(last + 1)) repeats --name")
        }
        guard isIdentifier(value) else {
            throw UsageError(
                "\(builder.label(last + 1)) has an invalid name \"\(value)\": "
                    + "a letter or _ then letters, digits, or _"
            )
        }
        builder.name = value
        entries[last] = .building(builder)
    }

    /// Marks the last question for `--stats` or `--distribution`. Every kind
    /// takes either flag, and each question takes each one once. Both flags
    /// on one question ask for the distribution, which holds the stats.
    private static func setDetail(
        _ flag: DetailFlag,
        to entries: inout [Entry]
    ) throws(UsageError) {
        var (last, builder) = try lastBuilder(entries, for: flag.rawValue)
        guard !builder[keyPath: flag.field] else {
            throw UsageError("\(builder.label(last + 1)) repeats \(flag.rawValue)")
        }
        builder[keyPath: flag.field] = true
        entries[last] = .building(builder)
    }

    /// Refuses a name that two questions share. Names are the ids the
    /// questions run under, and the library needs them unique.
    private static func checkUniqueNames(_ questions: [Question]) throws(UsageError) {
        var seen: Set<String> = []
        for question in questions {
            guard let name = question.name else { continue }
            guard seen.insert(name).inserted else {
                throw UsageError("question name \"\(name)\" is used twice")
            }
        }
    }

    /// Reads the value of a flag that takes one. Returns `nil` when the token
    /// is some other flag or a bare word. Accepts `--flag value` and
    /// `--flag=value`, and steps the index past a value it consumes.
    static func flagValue(
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
        guard isIdentifier(name) else {
            throw UsageError(
                "--context name \"\(name)\" is not valid: a letter or _ then letters, digits, or _"
            )
        }
        let rest = String(value[value.index(after: separator)...])
        guard !rest.isEmpty else { throw UsageError("--context \(name)= has no value") }
        let source = try contextSource(from: rest, as: "--context \(name)=")
        return .named(NamedContext(name: name, source: source))
    }

    /// Whether the text is an identifier: ASCII, a letter or `_` first, then
    /// letters, digits, or `_`. Context names and question names share the
    /// rule.
    static func isIdentifier(_ text: String) -> Bool {
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
            return Option(id: try checkedID(value, as: flag))
        }
        let id = try checkedID(String(value[value.startIndex..<separator]), as: flag)
        let description = String(value[value.index(after: separator)...])
        return Option(id: id, description: description.isEmpty ? nil : description)
    }

    /// The id of an `--option`, `--level`, `--yes`, or `--no` value, checked.
    /// An empty id is an error, and so is one holding a tab, a line feed, or
    /// a carriage return: a tab separates the fields of a line with `--stats`
    /// or `--distribution`, and a newline ends the line. The description
    /// takes any text.
    private static func checkedID(_ id: String, as flag: KindFlag) throws(UsageError) -> String {
        guard !id.isEmpty else { throw UsageError(flag.missingID) }
        let forbidden: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
        guard !id.unicodeScalars.contains(where: forbidden.contains) else {
            throw UsageError(flag.idHasWhitespace)
        }
        return id
    }
}
