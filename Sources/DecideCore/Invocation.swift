/// What one run of `decide` asks: one context and the questions about it.
///
/// The parser builds this from the command line. Nothing here touches a file
/// or the network. `ContextSource.file` names a path; the run reads it.
public struct Invocation: Sendable, Equatable {
    /// Where the context comes from.
    public var context: ContextSource
    /// The questions, in command-line order.
    public var questions: [Question]

    public init(context: ContextSource, questions: [Question]) {
        self.context = context
        self.questions = questions
    }
}

/// Where the context text comes from.
public enum ContextSource: Sendable, Equatable {
    /// The text itself, from `--context "..."`.
    case text(String)
    /// A path, from `--context @path`. The run reads it as UTF-8.
    case file(String)
}

/// One question and the kind of answer it takes.
public struct Question: Sendable, Equatable {
    /// What to judge, as the user typed it.
    public var instructions: String
    /// A choice from options or a rating on levels.
    public var kind: Kind

    public init(instructions: String, kind: Kind) {
        self.instructions = instructions
        self.kind = kind
    }

    /// The kind of question. The flags after the question decide it:
    /// `--option` makes a choice, `--level` makes a rating.
    public enum Kind: Sendable, Equatable {
        /// Pick one option. The answer is its id.
        case choice([Option])
        /// Place the context on an ordered scale, low to high. The answer is
        /// the id of the most likely level.
        case rating([Option])
    }
}

/// One answer the model can pick: an option of a choice or a level of a
/// rating. Both have an id and an optional description, so one struct serves
/// both.
public struct Option: Sendable, Equatable {
    /// The id the model reports and the tool prints.
    public var id: String
    /// What the option or level covers, from `id=description`. `nil` when the
    /// user gave only the id.
    public var description: String?

    public init(id: String, description: String? = nil) {
        self.id = id
        self.description = description
    }
}
