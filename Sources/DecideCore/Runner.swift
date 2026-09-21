import DecisionModels

/// One answered question, as the tool prints it.
public struct Outcome: Sendable, Equatable {
    /// The id the question ran under: `q1`, `q2`, and so on.
    public let questionID: String
    /// The id of the option or level the model picked.
    public let answer: String
    /// How sure the model is, from 0 to 1.
    public let confidence: Double
    /// The probability of every option or level, keyed by id.
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
    /// Ids are `q1` to `qN`, in question order. An option or level with no
    /// description uses its id as the criterion summary, because the id is
    /// what the model sees either way. Levels go on the wire as criteria in
    /// order; the read maps indices back to ids.
    public static func makeQuestionnaire(_ questions: [Question]) -> Questionnaire {
        Questionnaire(questions.enumerated().map { index, question in
            let kind: QuestionSpec.Kind = switch question.kind {
            case .choice(let options):
                .choice(options: options.map { option in
                    QuestionSpec.OptionSpec(
                        id: option.id,
                        criterion: Criterion(option.description ?? option.id)
                    )
                })
            case .rating(let levels):
                .rating(levels: levels.map { Criterion($0.description ?? $0.id) })
            }
            return QuestionSpec(
                id: identifier(at: index),
                instructions: .text(question.instructions),
                kind: kind
            )
        })
    }

    /// Sends every question in one request and returns the answers in question
    /// order.
    ///
    /// Confidence is the library's number over the whole scale. The read fills
    /// in every option or level the record leaves out at 0 before asking,
    /// because the record alone cannot know how many there are.
    ///
    /// Throws `DecisionError.malformedResponse` when a question comes back
    /// with no answer, with an answer of the wrong kind, or with a level index
    /// off the scale.
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
            switch questions[index].kind {
            case .choice(let options):
                guard case .choice(let reported, let probabilities, let confidence) = record else {
                    throw DecisionError.malformedResponse("The answer for \(id) is not a choice.")
                }
                var filled = probabilities
                for option in options where filled[option.id] == nil { filled[option.id] = 0 }
                let full = AnswerRecord.choice(
                    reported: reported, probabilities: filled, confidence: confidence
                )
                return Outcome(
                    questionID: id,
                    answer: reported,
                    confidence: full.confidence,
                    probabilities: filled
                )
            case .rating(let levels):
                guard case .rating(let score, let probabilities, let confidence) = record else {
                    throw DecisionError.malformedResponse("The answer for \(id) is not a rating.")
                }
                return try ratingOutcome(
                    questionID: id,
                    levels: levels,
                    score: score,
                    probabilities: probabilities,
                    reportedConfidence: confidence
                )
            }
        }
    }

    /// Turns a rating record into an outcome against the question's levels.
    ///
    /// The answer is the id of the most likely level, and a tie goes to the
    /// lower one. The outcome's probabilities are keyed by level id, with a
    /// level the record leaves out at 0. The confidence is the reported one,
    /// or the library's formula over all the levels. The score plays no part.
    ///
    /// Throws `DecisionError.malformedResponse` when the record names a level
    /// the question does not have.
    private static func ratingOutcome(
        questionID: String,
        levels: [Option],
        score: Double,
        probabilities: [Int: Double],
        reportedConfidence: Double?
    ) throws -> Outcome {
        for level in probabilities.keys.sorted() where !levels.indices.contains(level) {
            throw DecisionError.malformedResponse(
                "The answer for \(questionID) names level \(level), "
                    + "but the question has \(levels.count) levels."
            )
        }
        var filled = probabilities
        for level in levels.indices where filled[level] == nil { filled[level] = 0 }
        var best = 0
        var bestProbability = -Double.infinity
        for level in levels.indices {
            let probability = filled[level] ?? 0
            if probability > bestProbability {
                best = level
                bestProbability = probability
            }
        }
        var byID: [String: Double] = [:]
        for (level, option) in levels.enumerated() {
            byID[option.id] = filled[level] ?? 0
        }
        let full = AnswerRecord.rating(
            score: score, probabilities: filled, confidence: reportedConfidence
        )
        return Outcome(
            questionID: questionID,
            answer: levels[best].id,
            confidence: full.confidence,
            probabilities: byID
        )
    }

    /// The id of the question at `index`. The first question is `q1`.
    private static func identifier(at index: Int) -> String {
        "q\(index + 1)"
    }
}
