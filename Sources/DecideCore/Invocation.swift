/// What one run of `decide` asks: the questions, and the context they are
/// about, if any.
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

    public init(context: Context?, questions: [Question], quiet: Bool = false) {
        self.context = context
        self.questions = questions
        self.quiet = quiet
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

    public init(instructions: String, kind: Kind, minimumConfidence: Double? = nil) {
        self.instructions = instructions
        self.kind = kind
        self.minimumConfidence = minimumConfidence
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

    public init(id: String, description: String? = nil) {
        self.id = id
        self.description = description
    }
}
