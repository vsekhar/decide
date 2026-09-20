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

/// One classification question and the options the model picks from.
public struct Question: Sendable, Equatable {
    /// What to judge, as the user typed it.
    public var instructions: String
    /// The options, in command-line order.
    public var options: [Option]

    public init(instructions: String, options: [Option] = []) {
        self.instructions = instructions
        self.options = options
    }
}

/// One answer the model can pick.
public struct Option: Sendable, Equatable {
    /// The id the model reports and the tool prints.
    public var id: String
    /// What the option covers, from `--option id=description`. `nil` when the
    /// user gave only the id.
    public var description: String?

    public init(id: String, description: String? = nil) {
        self.id = id
        self.description = description
    }
}
