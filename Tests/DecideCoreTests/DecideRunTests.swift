import DecisionModels
import DecisionModelsTesting
import Foundation
import Synchronization
import Testing

@testable import DecideCore

@Suite("DecideRun")
struct DecideRunTests {
    /// The team question from the README, with its three options.
    private static let teamQuestion = [
        "Which team handles this ticket?",
        "--option", "shipping", "--option", "billing", "--option", "returns",
    ]
    /// The urgency question from the README, with its three levels.
    private static let urgencyQuestion = [
        "How urgent is this ticket?",
        "--level", "not_urgent", "--level", "somewhat_urgent", "--level", "urgent",
    ]
    /// The refund question from the README, with its two values.
    private static let refundQuestion = [
        "Should we issue a refund?",
        "--yes", "Yes", "--no", "No",
    ]
    /// The refund question with a bar after its two values.
    private static func refundQuestion(bar: String) -> [String] {
        refundQuestion + ["--min-confidence", bar]
    }

    /// What the scripted model answers: `q1` is the team, `q2` the urgency,
    /// and `q3` the refund a test asks for.
    private static func answers(refund: AnswerRecord) -> Answers {
        Answers(
            records: [
                "q1": .choice(
                    reported: "returns",
                    probabilities: ["returns": 0.91, "shipping": 0.06, "billing": 0.03],
                    confidence: 0.91
                ),
                "q2": .rating(
                    score: 1.15,
                    probabilities: [0: 0.15, 1: 0.55, 2: 0.30],
                    confidence: 0.78
                ),
                "q3": refund,
            ],
            quality: .calibrated
        )
    }

    /// A model that gives those answers and keeps the request it got. The
    /// refund comes back at P(yes) 0.87, so its confidence is 0.74.
    private static func triageModel(recording box: RequestBox? = nil) -> ScriptedModel {
        ScriptedModel { request in
            box?.record(request)
            return Self.answers(refund: .verdict(probability: 0.87))
        }
    }

    /// A model whose refund answer is P(yes) 0.6, so its confidence is 0.2.
    private static func unsureRefundModel() -> ScriptedModel {
        ScriptedModel(answering: Self.answers(refund: .verdict(probability: 0.6)))
    }

    @Test("The batch example prints one answer per question, in order")
    func batchExample() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion + Self.refundQuestion,
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "returns\nsomewhat_urgent\nYes\n")
        #expect(err.isEmpty)
    }

    @Test("A refund below its bar prints nothing and exits 2")
    func unsureBatch() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion + Self.refundQuestion(bar: "0.7"),
            environment: [:],
            model: Self.unsureRefundModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 2)
        #expect(out.isEmpty)
        #expect(
            err == """
                Error: unsure: question 3 ("Should we issue a refund?") has confidence 0.20, \
                below the bar of 0.70

                """
        )
    }

    @Test("The README batch example passes its own bar when the model is sure")
    func batchAtTheReadmeBar() async {
        var out = ""
        var err = ""

        // The scripted refund answer is P(yes) 0.87, confidence 0.74.
        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion + Self.refundQuestion(bar: "0.7"),
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "returns\nsomewhat_urgent\nYes\n")
        #expect(err.isEmpty)
    }

    @Test("The same answers clear a lower bar and print three lines")
    func batchUnderALowBar() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion + Self.refundQuestion(bar: "0.1"),
            environment: [:],
            model: Self.unsureRefundModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "returns\nsomewhat_urgent\nYes\n")
        #expect(err.isEmpty)
    }

    @Test("A bare question prints yes or no")
    func bareQuestion() async {
        let model = ScriptedModel(
            answering: Answers(records: ["q1": .verdict(probability: 0.2)], quality: .calibrated)
        )
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some message text", "Is this message spam?"],
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "no\n")
        #expect(err.isEmpty)
    }

    @Test("An @file context reaches the model as the file's text")
    func fileContext() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).txt")
        let text = "The parcel never arrived and I want my money back.\n"
        try text.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let box = RequestBox()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "@\(url.path)"] + Self.teamQuestion,
            environment: [:],
            model: Self.triageModel(recording: box),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "returns\n")
        #expect(err.isEmpty)
        let request = try #require(box.request)
        #expect(request.state == .text(text))
    }

    @Test("A missing context file exits 10 and reaches no model")
    func missingFile() async {
        let path = "/nonexistent/\(UUID().uuidString).txt"
        let model = Self.triageModel()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "@\(path)"] + Self.teamQuestion,
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains(path))
        #expect(out.isEmpty)
        #expect(model.callCount == 0)
    }

    @Test("No arguments prints the usage text on stderr and exits 10")
    func noArguments() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: [],
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("Error: no arguments given"))
        #expect(err.contains(Decide.usage))
        #expect(out.isEmpty)
    }

    @Test("An unknown flag names itself and prints the usage text")
    func unknownFlag() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--bogus", "--context", "text"] + Self.teamQuestion,
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.hasPrefix("Error: unknown flag: --bogus"))
        #expect(err.contains(Decide.usage))
        #expect(out.isEmpty)
    }

    @Test("--help prints the usage text on stdout and exits 0")
    func help() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--help"],
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == Decide.usage + "\n")
        #expect(err.isEmpty)
    }

    @Test("An empty environment and no injected model exits 10")
    func noModel() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion,
            environment: [:],
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("DECIDE_MODEL"))
        #expect(out.isEmpty)
    }

    @Test("A timeout exits 11 and leaves stdout empty")
    func timeout() async {
        let model = ScriptedModel { _ in throw DecisionError.timeout }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion,
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 11)
        #expect(err == "Error: the request timed out.\n")
        #expect(out.isEmpty)
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
