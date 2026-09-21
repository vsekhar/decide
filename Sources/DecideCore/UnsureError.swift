/// A run whose model answered, but with less confidence than a question
/// asked for. The tool prints no answer and exits 2.
public struct UnsureError: Error, Equatable, Sendable {
    /// The questions below their bar, in question order.
    public let questions: [Unsure]

    public init(questions: [Unsure]) {
        self.questions = questions
    }
}

/// One question whose answer fell below its bar.
public struct Unsure: Equatable, Sendable {
    /// The question's number on the command line. The first is 1.
    public let number: Int
    /// The question, as the user typed it.
    public let instructions: String
    /// The confidence the answer had.
    public let confidence: Double
    /// The confidence the question asked for.
    public let minimumConfidence: Double

    public init(number: Int, instructions: String, confidence: Double, minimumConfidence: Double) {
        self.number = number
        self.instructions = instructions
        self.confidence = confidence
        self.minimumConfidence = minimumConfidence
    }
}
