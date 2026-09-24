/// What one run of `decide` asks: the questions, the context they are about,
/// if any, and the model and key to use, when the line names them.
///
/// The parser builds this from the command line. Nothing here touches a file
/// or the network. `ContextSource.file` names a path; the run reads it.
public struct Invocation: Sendable, Equatable {
    /// Where the context comes from. `nil` is a run with no context: the
    /// questions carry their own facts.
    public var context: Context?
    /// The questions, in command-line order.
    public var questions: [Question]
    /// Print no answer, from `--quiet`. Only a run with one yes/no question
    /// may set it; the exit code carries the answer then.
    public var quiet: Bool
    /// Print the answers as one JSON object, from `--json`. Never with
    /// `quiet`.
    public var json: Bool
    /// The model for this run from `--model`, or nil to use the environment
    /// and the config files.
    public var model: String?
    /// The API key for this run from `--api-key`, or nil to use the
    /// environment and the config files.
    public var apiKey: String?

    public init(
        context: Context?,
        questions: [Question],
        quiet: Bool = false,
        json: Bool = false,
        model: String? = nil,
        apiKey: String? = nil
    ) {
        self.context = context
        self.questions = questions
        self.quiet = quiet
        self.json = json
        self.model = model
        self.apiKey = apiKey
    }

    /// The environment with this run's `--model` and `--api-key` laid over
    /// it: `DECIDE_MODEL` is `model` when that is set, and
    /// `DECIDE_MODEL_API_KEY` is `apiKey` when that is set. Every other
    /// variable passes through. Pure, so the precedence is testable without
    /// a model.
    public func applied(to environment: [String: String]) -> [String: String] {
        var environment = environment
        if let model { environment[ModelConfiguration.modelVariable] = model }
        if let apiKey { environment[ModelConfiguration.apiKeyVariable] = apiKey }
        return environment
    }
}

/// The context a run is about: one text, or an object of named texts.
public enum Context: Sendable, Equatable {
    /// One unnamed `--context`. The model sees its text as the state.
    case single(ContextSource)
    /// Every `--context <name>=...`, in command-line order. The model sees
    /// one JSON object keyed by name, so a question can refer to a name in
    /// prose. One named context is a one-field object. The parser keeps
    /// names unique; the run keeps the last of a repeat.
    case named([NamedContext])
}

/// One `--context <name>=...`: the name and where its text comes from.
public struct NamedContext: Sendable, Equatable {
    /// The field name in the object the model sees: a letter or `_`, then
    /// letters, digits, or `_`, all ASCII.
    public let name: String
    /// The text itself, or the file that holds it.
    public let source: ContextSource

    public init(name: String, source: ContextSource) {
        self.name = name
        self.source = source
    }
}

/// Where the context text comes from.
public enum ContextSource: Sendable, Equatable {
    /// The text itself, from `--context "..."` or `--context <name>=...`.
    case text(String)
    /// A path, from `--context @path` or `--context <name>=@path`. The run
    /// reads it as UTF-8.
    case file(String)
}

/// One question and the kind of answer it takes.
public struct Question: Sendable, Equatable {
    /// What to judge, as the user typed it.
    public var instructions: String
    /// A choice from options, a rating on levels, or a yes/no verdict.
    public var kind: Kind
    /// The confidence the answer needs, from `--min-confidence`. `nil` means
    /// no bar, so an absent flag never makes a run unsure.
    public var minimumConfidence: Double?
    /// What the question prints instead of its answer when that answer is
    /// below its bar, or when the run has a remote error, from `--fallback`
    /// or a JSON file's `fallback`. nil when the question has none. On a
    /// yes/no question it is the yes value or the no value, so the exit code
    /// of a one-question run still follows a side.
    public var fallback: String?
    /// The question's name: the id it runs under, and the key `--json`
    /// output will use. nil for an unnamed question, which runs as `q<N>`,
    /// N its position in the run.
    public var name: String?
    /// Rules the model applies with the question, from a JSON file's
    /// structured instructions. Empty for a plain question.
    public var rules: [String]
    /// What the question's line shows beyond its answer, from `--stats` and
    /// `--distribution`. `.distribution` includes `.stats`.
    public var detail: Detail

    public init(
        instructions: String,
        kind: Kind,
        minimumConfidence: Double? = nil,
        fallback: String? = nil,
        name: String? = nil,
        rules: [String] = [],
        detail: Detail = .answer
    ) {
        self.instructions = instructions
        self.kind = kind
        self.minimumConfidence = minimumConfidence
        self.fallback = fallback
        self.name = name
        self.rules = rules
        self.detail = detail
    }

    /// The kind of question. The flags after the question decide it:
    /// `--option` makes a choice, `--level` makes a rating, and neither makes
    /// a yes/no question, which `--yes` and `--no` decorate.
    public enum Kind: Sendable, Equatable {
        /// Pick one option. The answer is its id.
        case choice([Option])
        /// Place the context on an ordered scale, low to high. The answer is
        /// the id of the most likely level.
        case rating([Option])
        /// Answer yes or no. The answer is the yes value when P(yes) is at
        /// least 0.5, else the no value. A side's description, when given, is
        /// what counts as that side.
        case verdict(yes: Option, no: Option)
    }

    /// How much of an answer a question's line shows. The flags after the
    /// question choose it.
    public enum Detail: Sendable, Equatable {
        /// The answer alone, which a question with neither flag prints.
        case answer
        /// The answer and its numbers: the confidence, the answer's
        /// probability, and a rating's score, from `--stats`.
        case stats
        /// The numbers, then the probability of every option, level, or
        /// side, from `--distribution`.
        case distribution
    }
}

/// One answer the model can pick: an option of a choice, a level of a rating,
/// or a side of a yes/no question. Each has an id, the value to print, and an
/// optional description, so one struct serves all three.
public struct Option: Sendable, Equatable {
    /// The value the tool prints. For a choice, also the id the model reports.
    public var id: String
    /// What the option, level, or side covers, from `id=description`. `nil`
    /// when the user gave only the id.
    public var description: String?
    /// What the option, level, or side does not cover, from a JSON file's
    /// `not_for`. nil when not given.
    public var notFor: String?
    /// Short examples that belong to it, from a JSON file's `examples`.
    /// Empty when not given.
    public var examples: [String]
    /// Signals in the context that point to it, from a JSON file's
    /// `signals`. Empty when not given.
    public var signals: [String]

    public init(
        id: String,
        description: String? = nil,
        notFor: String? = nil,
        examples: [String] = [],
        signals: [String] = []
    ) {
        self.id = id
        self.description = description
        self.notFor = notFor
        self.examples = examples
        self.signals = signals
    }
}
