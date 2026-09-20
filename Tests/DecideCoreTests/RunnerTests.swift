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
            options: [
                DecideCore.Option(id: "shipping", description: "Delivery issues"),
                DecideCore.Option(id: "returns"),
                DecideCore.Option(id: "billing"),
            ]
        ),
        DecideCore.Question(
            instructions: "How urgent is it?",
            options: [
                DecideCore.Option(id: "urgent", description: "Needs a reply today"),
                DecideCore.Option(id: "routine"),
            ]
        ),
    ]
    static let context = "The parcel never arrived and I want my money back."
    static let teamProbabilities = ["returns": 0.91, "shipping": 0.06, "billing": 0.03]
    static let urgencyProbabilities = ["urgent": 0.7, "routine": 0.3]
    static let bothAnswers = Answers(
        records: [
            "q1": .choice(reported: "returns", probabilities: teamProbabilities, confidence: 0.91),
            "q2": .choice(reported: "urgent", probabilities: urgencyProbabilities, confidence: nil),
        ],
        quality: .calibrated
    )

    @Test("The questions become specs q1 and q2")
    func questionnaireShape() {
        let questionnaire = Runner.makeQuestionnaire(Self.questions)
        #expect(questionnaire.specs.map(\.id) == ["q1", "q2"])
        #expect(questionnaire.specs.map(\.instructions) == [
            .text("Which team owns this ticket?"),
            .text("How urgent is it?"),
        ])

        guard case .choice(let team) = questionnaire.specs[0].kind,
              case .choice(let urgency) = questionnaire.specs[1].kind
        else {
            Issue.record("Both questions must be choices.")
            return
        }
        #expect(team.map(\.id) == ["shipping", "returns", "billing"])
        #expect(urgency.map(\.id) == ["urgent", "routine"])
        // A description becomes the summary. A bare option uses its id.
        #expect(team[0].criterion.summary == "Delivery issues")
        #expect(team[1].criterion.summary == "returns")
        #expect(team[2].criterion.summary == "billing")
        #expect(urgency[0].criterion.summary == "Needs a reply today")
        #expect(urgency[1].criterion.summary == "routine")
    }

    @Test("Two questions make one request")
    func oneRequest() async throws {
        let box = RequestBox()
        let model = ScriptedModel { request in
            box.record(request)
            return Self.bothAnswers
        }
        let session = DecisionSession(model: model)

        _ = try await Runner.decide(Self.questions, about: Self.context, using: session)

        #expect(model.callCount == 1)
        let request = try #require(box.request)
        #expect(request.questionnaire.specs.count == 2)
        #expect(request.state == .text(Self.context))
    }

    @Test("The outcomes come back in question order")
    func outcomeOrder() async throws {
        let model = ScriptedModel(answering: Self.bothAnswers)
        let session = DecisionSession(model: model)

        let outcomes = try await Runner.decide(
            Self.questions, about: Self.context, using: session
        )

        #expect(outcomes.map(\.questionID) == ["q1", "q2"])
        #expect(outcomes.map(\.answer) == ["returns", "urgent"])
        #expect(outcomes[0].probabilities == Self.teamProbabilities)
        #expect(outcomes[1].probabilities == Self.urgencyProbabilities)
        // The first record reports its confidence. The second leaves the
        // library to work it out.
        #expect(outcomes[0].confidence == 0.91)
        let computed = AnswerRecord.choice(
            reported: "urgent", probabilities: Self.urgencyProbabilities, confidence: nil
        ).confidence
        #expect(outcomes[1].confidence == computed)
    }

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
                "q2": .choice(
                    reported: "urgent",
                    probabilities: Self.urgencyProbabilities,
                    confidence: nil
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
        #expect(message == "The answer for q1 is not a choice.")
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
