import DecisionModels

/// One answered question, as the tool prints it.
public struct Outcome: Sendable, Equatable {
    /// The id the question ran under: `q1`, `q2`, and so on.
    public let questionID: String
    /// The id of the option or level the model picked, or the yes or no
    /// value.
    public let answer: String
    /// How sure the model is, from 0 to 1.
    public let confidence: Double
    /// The probability of every option or level, keyed by id, or of the yes
    /// and no values.
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
    /// order; the read maps indices back to ids. A yes or no value with no
    /// description sends no criterion, because the value is a label, not a
    /// description of the case.
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
            case .verdict(let yes, let no):
                .verdict(
                    ifTrue: yes.description.map { Criterion($0) },
                    ifFalse: no.description.map { Criterion($0) }
                )
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
    /// A `nil` context sends the request with no state, for questions that
    /// carry their own facts.
    ///
    /// The library checks each record against its question before the tool
    /// sees it: the kind matches, every index and probability is on the
    /// scale, a reported confidence lies in 0 to 1, and every option or level
    /// the provider left out is present at 0. So `Outcome.confidence` is the
    /// section 6.1 number over the whole scale.
    ///
    /// Throws `DecisionError.malformedResponse` when a question comes back
    /// with no answer, or when the library rejects a record. Throws
    /// `UnsureError` when a question with a bar gets an answer below it. The
    /// bar compares against the same number `Outcome.confidence` holds.
    public static func decide(
        _ questions: [Question],
        about context: String?,
        using session: DecisionSession
    ) async throws -> [Outcome] {
        let questionnaire = makeQuestionnaire(questions)
        let answers: Answers
        if let context {
            answers = try await session.decide(questionnaire, about: context)
        } else {
            answers = try await session.decide(questionnaire)
        }
        let outcomes: [Outcome] = try questions.indices.map { index in
            let id = identifier(at: index)
            guard let record = answers.records[id] else {
                throw DecisionError.malformedResponse("The response holds no answer for \(id).")
            }
            // The library has matched each record's kind to its question, so
            // these guards only unpack the record.
            switch questions[index].kind {
            case .choice:
                guard case .choice(let reported, let probabilities, _) = record else {
                    throw DecisionError.malformedResponse("The answer for \(id) is not a choice.")
                }
                return Outcome(
                    questionID: id,
                    answer: reported,
                    confidence: record.confidence,
                    probabilities: probabilities
                )
            case .rating(let levels):
                guard case .rating(_, let probabilities, _) = record else {
                    throw DecisionError.malformedResponse("The answer for \(id) is not a rating.")
                }
                return ratingOutcome(
                    questionID: id,
                    levels: levels,
                    probabilities: probabilities,
                    confidence: record.confidence
                )
            case .verdict(let yes, let no):
                guard case .verdict(let probability) = record else {
                    throw DecisionError.malformedResponse("The answer for \(id) is not a verdict.")
                }
                return verdictOutcome(
                    questionID: id, yes: yes, no: no, probability: probability
                )
            }
        }
        let unsure = questions.indices.compactMap { index -> Unsure? in
            guard let bar = questions[index].minimumConfidence,
                  outcomes[index].confidence < bar
            else { return nil }
            return Unsure(
                number: index + 1,
                instructions: questions[index].instructions,
                confidence: outcomes[index].confidence,
                minimumConfidence: bar
            )
        }
        guard unsure.isEmpty else { throw UnsureError(questions: unsure) }
        return outcomes
    }

    /// Turns a rating record into an outcome against the question's levels.
    ///
    /// The answer is the id of the most likely level, and a tie goes to the
    /// lower one. The outcome's probabilities are keyed by level id. The
    /// library has already put every index on the scale and every level in
    /// the record, so the confidence it computed is exact.
    private static func ratingOutcome(
        questionID: String,
        levels: [Option],
        probabilities: [Int: Double],
        confidence: Double
    ) -> Outcome {
        var best = 0
        var bestProbability = -Double.infinity
        for level in levels.indices {
            let probability = probabilities[level] ?? 0
            if probability > bestProbability {
                best = level
                bestProbability = probability
            }
        }
        var byID: [String: Double] = [:]
        for (level, option) in levels.enumerated() {
            byID[option.id] = probabilities[level] ?? 0
        }
        return Outcome(
            questionID: questionID,
            answer: levels[best].id,
            confidence: confidence,
            probabilities: byID
        )
    }

    /// Turns a verdict probability into an outcome against the question's two
    /// sides.
    ///
    /// The probability is P(yes), which the library has already kept in 0 to
    /// 1. The answer is the yes value when it reaches 0.5, else the no value.
    /// The confidence is the library's number.
    private static func verdictOutcome(
        questionID: String,
        yes: Option,
        no: Option,
        probability: Double
    ) -> Outcome {
        let full = AnswerRecord.verdict(probability: probability)
        // Two assignments, not a literal: a literal traps on a repeated key,
        // and the parser's guard against one value for both sides should not
        // be the only thing standing between a bad question and a crash.
        var probabilities: [String: Double] = [:]
        probabilities[yes.id] = probability
        probabilities[no.id] = 1 - probability
        return Outcome(
            questionID: questionID,
            answer: probability >= 0.5 ? yes.id : no.id,
            confidence: full.confidence,
            probabilities: probabilities
        )
    }

    /// The id of the question at `index`. The first question is `q1`.
    private static func identifier(at index: Int) -> String {
        "q\(index + 1)"
    }
}
