import DecisionModels

/// One answered question, as the tool prints it.
public struct Outcome: Sendable, Equatable {
    /// The id the question ran under: `q1`, `q2`, and so on.
    public let questionID: String
    /// The id of the option the model picked.
    public let answer: String
    /// How sure the model is, from 0 to 1.
    public let confidence: Double
    /// The probability of every option the model reported.
    public let probabilities: [String: Double]

    public init(
        questionID: String,
        answer: String,
        confidence: Double,
        probabilities: [String: Double]
    ) {
        self.questionID = questionID
        self.answer = answer
        self.confidence = confidence
        self.probabilities = probabilities
    }
}

/// Sends the questions and reads the answers back.
public enum Runner {
    /// Turns the parsed questions into one questionnaire.
    ///
    /// Ids are `q1` to `qN`, in question order. An option with no description
    /// uses its id as the criterion summary, because the id is what the model
    /// sees either way.
    public static func makeQuestionnaire(_ questions: [Question]) -> Questionnaire {
        Questionnaire(questions.enumerated().map { index, question in
            QuestionSpec(
                id: identifier(at: index),
                instructions: .text(question.instructions),
                kind: .choice(options: question.options.map { option in
                    QuestionSpec.OptionSpec(
                        id: option.id,
                        criterion: Criterion(option.description ?? option.id)
                    )
                })
            )
        })
    }

    /// Sends every question in one request and returns the answers in question
    /// order.
    ///
    /// Throws `DecisionError.malformedResponse` when a question comes back
    /// with no answer, or with an answer that is not a choice.
    public static func decide(
        _ questions: [Question],
        about context: String,
        using session: DecisionSession
    ) async throws -> [Outcome] {
        let questionnaire = makeQuestionnaire(questions)
        let answers = try await session.decide(questionnaire, about: context)
        return try questions.indices.map { index in
            let id = identifier(at: index)
            guard let record = answers.records[id] else {
                throw DecisionError.malformedResponse("The response holds no answer for \(id).")
            }
            guard case .choice(let reported, let probabilities, _) = record else {
                throw DecisionError.malformedResponse("The answer for \(id) is not a choice.")
            }
            return Outcome(
                questionID: id,
                answer: reported,
                confidence: record.confidence,
                probabilities: probabilities
            )
        }
    }

    /// The id of the question at `index`. The first question is `q1`.
    private static func identifier(at index: Int) -> String {
        "q\(index + 1)"
    }
}
