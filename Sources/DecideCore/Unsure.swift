import Foundation

/// One question whose answer fell below its `--min-confidence` bar. The run
/// prints an empty answer on its line, reports every such question on stderr
/// through `report`, and exits 2.
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

    /// The stderr line for the unsure questions, in question order, with no
    /// trailing newline: `Unsure: question 3 ("Should we issue a refund?")
    /// has confidence 0.20, below the bar of 0.70`, one clause per question,
    /// joined by `; `. Two decimals, so the line reads at a glance; `--stats`
    /// prints three and `--json` the exact value. One line whatever the
    /// question text holds.
    public static func report(_ questions: [Unsure]) -> String {
        let clauses = questions.map { question in
            "question \(question.number) (\"\(question.instructions)\") "
                + "has confidence \(String(format: "%.2f", question.confidence)), "
                + "below the bar of \(String(format: "%.2f", question.minimumConfidence))"
        }
        return ExitCode.oneLine("Unsure: " + clauses.joined(separator: "; "))
    }
}
