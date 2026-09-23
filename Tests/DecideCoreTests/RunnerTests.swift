import DecisionModels
import DecisionModelsTesting
import Synchronization
import Testing

@testable import DecideCore

@Suite("Runner")
struct RunnerTests {
    // The library also has a `Question`, so the tests name the module.
    static let questions = [
        DecideCore.Question(
            instructions: "Which team owns this ticket?",
            kind: .choice([
                DecideCore.Option(id: "shipping", description: "Delivery issues"),
                DecideCore.Option(id: "returns"),
                DecideCore.Option(id: "billing"),
            ])
        ),
        DecideCore.Question(
            instructions: "How urgent is it?",
            kind: .rating([
                DecideCore.Option(id: "not_urgent"),
                DecideCore.Option(
                    id: "somewhat_urgent",
                    description: "Customer problem, but customer not blocked"
                ),
                DecideCore.Option(id: "urgent"),
            ])
        ),
        DecideCore.Question(
            instructions: "Should we issue a refund?",
            kind: .verdict(yes: DecideCore.Option(id: "Yes"), no: DecideCore.Option(id: "No"))
        ),
    ]
    static let context: State = .text("The parcel never arrived and I want my money back.")
    static let teamProbabilities = ["returns": 0.91, "shipping": 0.06, "billing": 0.03]
    /// What the model reports for the rating, keyed by level index.
    static let urgencyProbabilities = [0: 0.15, 1: 0.55, 2: 0.30]
    /// The same numbers as the outcome keys them, by level id.
    static let urgencyByLevel = ["not_urgent": 0.15, "somewhat_urgent": 0.55, "urgent": 0.30]
    /// What the model reports for the verdict: P(yes).
    static let refundProbability = 0.87
    static let allAnswers = answers(
        urgency: .rating(score: 1.2, probabilities: urgencyProbabilities, confidence: 0.78)
    )

    /// What the model reports for the team: the whole scale, confidence and
    /// all.
    static let teamAnswer = AnswerRecord.choice(
        reported: "returns", probabilities: teamProbabilities, confidence: 0.91
    )

    /// What the model reports for the rating, for the tests that vary
    /// another question.
    static let urgencyAnswer = AnswerRecord.rating(
        score: 1.2, probabilities: urgencyProbabilities, confidence: 0.78
    )

    /// The urgency record a test wants for `q2`, the refund record it wants
    /// for `q3`, and the team record it wants for `q1`.
    static func answers(
        urgency record: AnswerRecord,
        refund: AnswerRecord = .verdict(probability: refundProbability),
        team: AnswerRecord = teamAnswer
    ) -> Answers {
        Answers(
            records: [
                "q1": team,
                "q2": record,
                "q3": refund,
            ],
            quality: .calibrated
        )
    }

    /// The three questions again, each with the bar at its place. `nil` is no
    /// bar, so a test gates only the question it cares about.
    static func questions(bars: [Double?]) -> [DecideCore.Question] {
        zip(questions, bars).map { question, bar in
            DecideCore.Question(
                instructions: question.instructions,
                kind: question.kind,
                minimumConfidence: bar
            )
        }
    }

    @Test("The questions become specs q1, q2, and q3")
    func questionnaireShape() {
        let questionnaire = Runner.makeQuestionnaire(Self.questions)
        #expect(questionnaire.specs.map(\.id) == ["q1", "q2", "q3"])
        #expect(questionnaire.specs.map(\.instructions) == [
            .text("Which team owns this ticket?"),
            .text("How urgent is it?"),
            .text("Should we issue a refund?"),
        ])

        guard case .choice(let team) = questionnaire.specs[0].kind,
              case .rating(let urgency) = questionnaire.specs[1].kind,
              case .verdict(let ifTrue, let ifFalse) = questionnaire.specs[2].kind
        else {
            Issue.record("The three questions must be a choice, a rating, and a verdict.")
            return
        }
        #expect(team.map(\.id) == ["shipping", "returns", "billing"])
        // A description becomes the summary. A bare option uses its id.
        #expect(team[0].criterion.summary == "Delivery issues")
        #expect(team[1].criterion.summary == "returns")
        #expect(team[2].criterion.summary == "billing")
        // Levels carry no id on the wire, only a criterion, in order.
        #expect(urgency.map(\.summary) == [
            "not_urgent",
            "Customer problem, but customer not blocked",
            "urgent",
        ])
        // A bare yes or no value is a label, so it sends no criterion.
        #expect(ifTrue == nil)
        #expect(ifFalse == nil)
    }

    @Test("A described yes or no side sends its description as the criterion")
    func describedVerdictSpec() {
        let question = DecideCore.Question(
            instructions: "Should we issue a refund?",
            kind: .verdict(
                yes: DecideCore.Option(id: "Yes", description: "The policy allows it"),
                no: DecideCore.Option(id: "No", description: "The policy forbids it")
            )
        )
        let questionnaire = Runner.makeQuestionnaire([question])

        guard case .verdict(let ifTrue, let ifFalse) = questionnaire.specs[0].kind else {
            Issue.record("The question must be a verdict.")
            return
        }
        #expect(ifTrue?.summary == "The policy allows it")
        #expect(ifFalse?.summary == "The policy forbids it")
    }

    @Test("A choice, a rating, and a verdict make one request")
    func oneRequest() async throws {
        let box = RequestBox()
        let model = ScriptedModel { request in
            box.record(request)
            return Self.allAnswers
        }
        let session = DecisionSession(model: model)

        _ = try await Runner.decide(Self.questions, about: Self.context, using: session)

        #expect(model.callCount == 1)
        let request = try #require(box.request)
        #expect(request.questionnaire.specs.count == 3)
        #expect(request.state == Self.context)
    }

    @Test("An object of named contexts sends the request with that object as its state")
    func namedContextsRequest() async throws {
        let box = RequestBox()
        let model = ScriptedModel { request in
            box.record(request)
            return Self.allAnswers
        }
        let session = DecisionSession(model: model)

        _ = try await Runner.decide(
            Self.questions,
            about: .object(["ticket": .text("t"), "refund_policy": .text("p")]),
            using: session
        )

        #expect(model.callCount == 1)
        let request = try #require(box.request)
        #expect(request.state == .object(["ticket": .text("t"), "refund_policy": .text("p")]))
    }

    @Test("A nil context sends a request with no state")
    func noContextRequest() async throws {
        let box = RequestBox()
        let model = ScriptedModel { request in
            box.record(request)
            return Self.allAnswers
        }
        let session = DecisionSession(model: model)

        _ = try await Runner.decide(Self.questions, about: nil, using: session)

        #expect(model.callCount == 1)
        let request = try #require(box.request)
        #expect(request.state == nil)
    }

    @Test("The outcomes come back in question order")
    func outcomeOrder() async throws {
        let model = ScriptedModel(answering: Self.allAnswers)
        let session = DecisionSession(model: model)

        let outcomes = try await Runner.decide(
            Self.questions, about: Self.context, using: session
        )

        #expect(outcomes.map(\.questionID) == ["q1", "q2", "q3"])
        // The rating answers with the id of its most likely level, and the
        // verdict with its yes value, because P(yes) is 0.87.
        #expect(outcomes.map(\.answer) == ["returns", "somewhat_urgent", "Yes"])
        #expect(outcomes[0].probabilities == Self.teamProbabilities)
        #expect(outcomes[1].probabilities == Self.urgencyByLevel)
        #expect(outcomes[0].confidence == 0.91)
        #expect(outcomes[1].confidence == 0.78)
    }

    @Test("A verdict answers with the yes value from 0.5 up, the no value below")
    func verdictThreshold() async throws {
        for (probability, answer) in [(0.87, "Yes"), (0.3, "No"), (0.5, "Yes")] {
            let session = DecisionSession(
                model: ScriptedModel(
                    answering: Self.answers(
                        urgency: .rating(
                            score: 1.2, probabilities: Self.urgencyProbabilities, confidence: 0.78
                        ),
                        refund: .verdict(probability: probability)
                    )
                )
            )

            let outcomes = try await Runner.decide(
                Self.questions, about: Self.context, using: session
            )

            #expect(outcomes[2].answer == answer)
        }
    }

    @Test("A verdict carries both values and the library's confidence")
    func verdictProbabilities() async throws {
        let session = DecisionSession(model: ScriptedModel(answering: Self.allAnswers))

        let outcomes = try await Runner.decide(
            Self.questions, about: Self.context, using: session
        )

        #expect(outcomes[2].probabilities["Yes"] == 0.87)
        let no = try #require(outcomes[2].probabilities["No"])
        // 1 - 0.87 is a floating-point result, so it needs a tolerance.
        #expect(abs(no - 0.13) < 1e-9)
        #expect(outcomes[2].confidence == AnswerRecord.verdict(probability: 0.87).confidence)
        // The library's formula is abs(2p - 1).
        #expect(abs(outcomes[2].confidence - 0.74) < 1e-9)
    }

    @Test("A probability outside 0 to 1 is a malformed response")
    func probabilityOffTheScale() async {
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: .rating(
                        score: 1.2, probabilities: Self.urgencyProbabilities, confidence: 0.78
                    ),
                    refund: .verdict(probability: 1.2)
                )
            )
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q3 has a probability outside 0...1.")
    }

    @Test("A choice under a verdict question is a malformed response")
    func choiceUnderVerdict() async {
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: .rating(
                        score: 1.2, probabilities: Self.urgencyProbabilities, confidence: 0.78
                    ),
                    refund: .choice(
                        reported: "Yes", probabilities: ["Yes": 0.9, "No": 0.1], confidence: 0.9
                    )
                )
            )
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q3 expects a verdict, but the record holds a choice.")
    }

    @Test("A record that reports no confidence takes the library's number")
    func reportedConfidence() async throws {
        let record = AnswerRecord.rating(
            score: 1.2, probabilities: Self.urgencyProbabilities, confidence: nil
        )
        let session = DecisionSession(model: ScriptedModel(answering: Self.answers(urgency: record)))

        let outcomes = try await Runner.decide(
            Self.questions, about: Self.context, using: session
        )

        // 1 - sigma / ((n - 1) / 2) over indices 0, 1, 2 with n = 3:
        // mean 1.15, variance 0.4275, sigma 0.6538.
        #expect(abs(outcomes[1].confidence - 0.3462) < 0.001)
    }

    @Test("A level the record leaves out still counts in the confidence")
    func omittedLevelConfidence() async throws {
        // Two of three levels. A raw record would read as a two-level scale
        // and give 0.08; the library fills the third level in, so 0.54
        // reaches the tool.
        let record = AnswerRecord.rating(score: 0.3, probabilities: [0: 0.7, 1: 0.3], confidence: nil)
        let session = DecisionSession(model: ScriptedModel(answering: Self.answers(urgency: record)))

        let outcomes = try await Runner.decide(
            Self.questions, about: Self.context, using: session
        )

        #expect(abs(outcomes[1].confidence - 0.5417) < 0.001)
    }

    @Test("An option the record leaves out still counts in the confidence")
    func omittedOptionConfidence() async throws {
        // Two of three options. Entropy 0.6109 over ln 3 gives 0.44; a raw
        // record would imply ln 2 and give 0.12. The library fills the third
        // option in.
        let answers = Answers(
            records: [
                "q1": .choice(
                    reported: "returns", probabilities: ["returns": 0.7, "shipping": 0.3], confidence: nil
                ),
                "q2": .rating(score: 1.2, probabilities: Self.urgencyProbabilities, confidence: 0.78),
                "q3": .verdict(probability: Self.refundProbability),
            ],
            quality: .calibrated
        )
        let session = DecisionSession(model: ScriptedModel(answering: answers))

        let outcomes = try await Runner.decide(
            Self.questions, about: Self.context, using: session
        )

        #expect(abs(outcomes[0].confidence - 0.4439) < 0.001)
        #expect(outcomes[0].probabilities == ["returns": 0.7, "shipping": 0.3, "billing": 0])
    }

    @Test("A verdict under a rating question is a malformed response")
    func verdictUnderRating() async {
        let session = DecisionSession(
            model: ScriptedModel(answering: Self.answers(urgency: .verdict(probability: 0.9)))
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q2 expects a rating, but the record holds a verdict.")
    }

    @Test("A reported confidence that is not a number is a malformed response")
    func reportedConfidenceNaN() async {
        let team = AnswerRecord.choice(
            reported: "returns", probabilities: Self.teamProbabilities, confidence: .nan
        )
        let session = DecisionSession(model: ScriptedModel(answering: Self.answers(urgency: Self.urgencyAnswer, team: team)))

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q1 reports a confidence outside 0...1.")
    }

    @Test("A reported confidence above 1 is a malformed response")
    func reportedConfidenceTooHigh() async {
        let urgency = AnswerRecord.rating(
            score: 1.2, probabilities: Self.urgencyProbabilities, confidence: 1.5
        )
        let session = DecisionSession(model: ScriptedModel(answering: Self.answers(urgency: urgency)))

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q2 reports a confidence outside 0...1.")
    }

    @Test("A rating under a choice question is a malformed response")
    func ratingUnderChoice() async {
        let answers = Answers(
            records: [
                "q1": .rating(score: 1.0, probabilities: [0: 0.5, 1: 0.5], confidence: nil),
                "q2": .rating(score: 1.2, probabilities: Self.urgencyProbabilities, confidence: 0.78),
                "q3": .verdict(probability: Self.refundProbability),
            ],
            quality: .calibrated
        )
        let session = DecisionSession(model: ScriptedModel(answering: answers))

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q1 expects a choice, but the record holds a rating.")
    }

    @Test("A tie between levels goes to the lower one")
    func ratingTie() async throws {
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: .rating(
                        score: 1.0, probabilities: [0: 0.4, 1: 0.2, 2: 0.4], confidence: 0.4
                    )
                )
            )
        )

        let outcomes = try await Runner.decide(
            Self.questions, about: Self.context, using: session
        )

        #expect(outcomes[1].answer == "not_urgent")
    }

    @Test("A level the record leaves out has probability 0")
    func ratingAbsentLevel() async throws {
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: .rating(score: 1.4, probabilities: [1: 0.6, 2: 0.4], confidence: 0.6)
                )
            )
        )

        let outcomes = try await Runner.decide(
            Self.questions, about: Self.context, using: session
        )

        #expect(outcomes[1].answer == "somewhat_urgent")
        #expect(
            outcomes[1].probabilities == ["not_urgent": 0, "somewhat_urgent": 0.6, "urgent": 0.4]
        )
    }

    @Test("A level off the scale is a malformed response")
    func levelOffTheScale() async {
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: .rating(score: 2.0, probabilities: [2: 0.4, 3: 0.6], confidence: 0.6)
                )
            )
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q2 has no level at index 3.")
    }

    // The library checks each record against its question before the runner
    // sees it, so the messages below are the library's, surfaced unchanged.
    @Test("A missing answer is a malformed response")
    func missingAnswer() async {
        let answers = Answers(
            records: [
                "q1": .choice(
                    reported: "returns", probabilities: Self.teamProbabilities, confidence: 0.91
                ),
            ],
            quality: .calibrated
        )
        let session = DecisionSession(model: ScriptedModel(answering: answers))

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "The response holds no answer for q2.")
    }

    @Test("An answer of the wrong kind is a malformed response")
    func wrongKind() async {
        let answers = Answers(
            records: [
                "q1": .verdict(probability: 0.5),
                "q2": .rating(
                    score: 1.2, probabilities: Self.urgencyProbabilities, confidence: 0.78
                ),
                "q3": .verdict(probability: Self.refundProbability),
            ],
            quality: .calibrated
        )
        let session = DecisionSession(model: ScriptedModel(answering: answers))

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q1 expects a choice, but the record holds a verdict.")
    }

    @Test("A choice below its bar is unsure, and one above it is not")
    func choiceBar() async throws {
        for (reported, bar, unsure) in [(0.6, 0.7, true), (0.8, 0.7, false)] {
            let session = DecisionSession(
                model: ScriptedModel(
                    answering: Self.answers(
                        urgency: Self.urgencyAnswer,
                        team: .choice(
                            reported: "returns",
                            probabilities: Self.teamProbabilities,
                            confidence: reported
                        )
                    )
                )
            )
            let questions = Self.questions(bars: [bar, nil, nil])

            if unsure {
                let error = await #expect(throws: UnsureError.self) {
                    _ = try await Runner.decide(questions, about: Self.context, using: session)
                }
                #expect(
                    error
                        == UnsureError(questions: [
                            Unsure(
                                number: 1,
                                instructions: "Which team owns this ticket?",
                                confidence: reported,
                                minimumConfidence: bar
                            )
                        ])
                )
            } else {
                let outcomes = try await Runner.decide(
                    questions, about: Self.context, using: session
                )
                #expect(outcomes[0].answer == "returns")
            }
        }
    }

    @Test("A choice with no reported confidence is gated on the library's number")
    func choiceBarWithoutReportedConfidence() async throws {
        // 0.91/0.06/0.03 over three options gives about 0.67.
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: Self.urgencyAnswer,
                    team: .choice(
                        reported: "returns",
                        probabilities: Self.teamProbabilities,
                        confidence: nil
                    )
                )
            )
        )

        let outcomes = try await Runner.decide(
            Self.questions(bars: [0.6, nil, nil]), about: Self.context, using: session
        )
        #expect(outcomes[0].answer == "returns")

        await #expect(throws: UnsureError.self) {
            _ = try await Runner.decide(
                Self.questions(bars: [0.7, nil, nil]), about: Self.context, using: session
            )
        }
    }

    @Test("A rating is gated on its confidence over the whole scale")
    func ratingBar() async throws {
        // The three levels with no reported confidence give 0.3462.
        let record = AnswerRecord.rating(
            score: 1.2, probabilities: Self.urgencyProbabilities, confidence: nil
        )
        let session = DecisionSession(model: ScriptedModel(answering: Self.answers(urgency: record)))

        let outcomes = try await Runner.decide(
            Self.questions(bars: [nil, 0.3, nil]), about: Self.context, using: session
        )
        #expect(outcomes[1].answer == "somewhat_urgent")

        await #expect(throws: UnsureError.self) {
            _ = try await Runner.decide(
                Self.questions(bars: [nil, 0.4, nil]), about: Self.context, using: session
            )
        }
    }

    @Test("A verdict near 0.5 is unsure, and a confident yes or no is not")
    func verdictBar() async throws {
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: Self.urgencyAnswer, refund: .verdict(probability: 0.6)
                )
            )
        )

        await #expect(throws: UnsureError.self) {
            _ = try await Runner.decide(
                Self.questions(bars: [nil, nil, 0.7]), about: Self.context, using: session
            )
        }

        for (probability, answer) in [(0.05, "No"), (0.95, "Yes")] {
            let confident = DecisionSession(
                model: ScriptedModel(
                    answering: Self.answers(
                        urgency: Self.urgencyAnswer,
                        refund: .verdict(probability: probability)
                    )
                )
            )

            let outcomes = try await Runner.decide(
                Self.questions(bars: [nil, nil, 0.7]), about: Self.context, using: confident
            )

            #expect(outcomes[2].answer == answer)
        }
    }

    @Test("Two questions below their bars are both listed, in order")
    func twoUnsureQuestions() async {
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: Self.urgencyAnswer,
                    refund: .verdict(probability: 0.6),
                    team: .choice(
                        reported: "returns",
                        probabilities: Self.teamProbabilities,
                        confidence: 0.6
                    )
                )
            )
        )

        let error = await #expect(throws: UnsureError.self) {
            _ = try await Runner.decide(
                Self.questions(bars: [0.7, nil, 0.8]), about: Self.context, using: session
            )
        }

        #expect(
            error
                == UnsureError(questions: [
                    Unsure(
                        number: 1,
                        instructions: "Which team owns this ticket?",
                        confidence: 0.6,
                        minimumConfidence: 0.7
                    ),
                    Unsure(
                        number: 3,
                        instructions: "Should we issue a refund?",
                        // The library's number for P(yes) 0.6, to the last bit.
                        confidence: AnswerRecord.verdict(probability: 0.6).confidence,
                        minimumConfidence: 0.8
                    ),
                ])
        )
    }

    @Test("Confidence 0 clears a bar of 0, and no bar clears anything")
    func zeroBar() async throws {
        // A verdict at 0.5 has confidence abs(2p - 1), which is 0.
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: Self.urgencyAnswer, refund: .verdict(probability: 0.5)
                )
            )
        )

        let gated = try await Runner.decide(
            Self.questions(bars: [nil, nil, 0]), about: Self.context, using: session
        )
        #expect(gated[2].confidence == 0)
        #expect(gated[2].answer == "Yes")

        let ungated = try await Runner.decide(
            Self.questions(bars: [nil, nil, nil]), about: Self.context, using: session
        )
        #expect(ungated[2].answer == "Yes")
    }

    @Test("A choice under a rating question is a malformed response")
    func choiceUnderRating() async {
        let session = DecisionSession(
            model: ScriptedModel(
                answering: Self.answers(
                    urgency: .choice(
                        reported: "urgent",
                        probabilities: ["urgent": 0.7, "not_urgent": 0.3],
                        confidence: 0.7
                    )
                )
            )
        )

        let error = await #expect(throws: DecisionError.self) {
            _ = try await Runner.decide(Self.questions, about: Self.context, using: session)
        }

        guard case .malformedResponse(let message) = error else {
            Issue.record("Expected a malformed response, got \(String(describing: error)).")
            return
        }
        #expect(message == "Question q2 expects a rating, but the record holds a choice.")
    }
}

/// Keeps the request the model got, so a test can read it after the call.
///
/// `Mutex` cannot be copied, so it lives behind a reference and the script
/// closure captures the box.
private final class RequestBox: Sendable {
    private let stored = Mutex<DecisionRequest?>(nil)

    func record(_ request: DecisionRequest) {
        stored.withLock { $0 = request }
    }

    var request: DecisionRequest? {
        stored.withLock { $0 }
    }
}
