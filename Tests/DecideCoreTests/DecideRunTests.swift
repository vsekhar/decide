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

    /// A model that gives those answers for the questions the request asks,
    /// as a provider would, and keeps the request it got. The refund comes
    /// back at P(yes) 0.87, so its confidence is 0.74.
    private static func triageModel(recording box: RequestBox? = nil) -> ScriptedModel {
        ScriptedModel { request in
            box?.record(request)
            let all = Self.answers(refund: .verdict(probability: 0.87))
            let asked = Set(request.questionnaire.specs.map(\.id))
            return Answers(
                records: all.records.filter { asked.contains($0.key) },
                quality: all.quality
            )
        }
    }

    /// A model whose refund answer is P(yes) 0.6, so its confidence is 0.2.
    private static func unsureRefundModel() -> ScriptedModel {
        ScriptedModel(answering: Self.answers(refund: .verdict(probability: 0.6)))
    }

    /// A model that answers one yes/no question, `q1`, at that P(yes).
    private static func spamModel(probability: Double) -> ScriptedModel {
        ScriptedModel(
            answering: Answers(
                records: ["q1": .verdict(probability: probability)],
                quality: .calibrated
            )
        )
    }

    /// The spam question from the README, with no question flags.
    private static let spamQuestion = ["--context", "some message text", "Is this message spam?"]

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

    @Test("A bare question prints yes and exits 0")
    func bareQuestionYes() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion,
            environment: [:],
            model: Self.spamModel(probability: 0.8),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "yes\n")
        #expect(err.isEmpty)
    }

    @Test("A bare question prints no and exits 1")
    func bareQuestionNo() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion,
            environment: [:],
            model: Self.spamModel(probability: 0.2),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 1)
        #expect(out == "no\n")
        #expect(err.isEmpty)
    }

    @Test("Custom values print the no value and exit 1")
    func customVerdictValues() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion + ["--yes", "spam", "--no", "ham"],
            environment: [:],
            model: Self.spamModel(probability: 0.2),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 1)
        #expect(out == "ham\n")
        #expect(err.isEmpty)
    }

    @Test("Custom values keep the yes side at exit 0")
    func customVerdictYes() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion + ["--yes", "spam", "--no", "ham"],
            environment: [:],
            model: Self.spamModel(probability: 0.8),
            stdout: &out,
            stderr: &err
        )

        // The code follows the yes side's value, not the literal "yes".
        #expect(code == 0)
        #expect(out == "spam\n")
        #expect(err.isEmpty)
    }

    @Test("A batch that starts with a yes/no question still exits 0")
    func verdictFirstBatch() async {
        let answers = Answers(
            records: [
                "q1": .verdict(probability: 0.2),
                "q2": .choice(
                    reported: "returns",
                    probabilities: ["returns": 0.91, "shipping": 0.06, "billing": 0.03],
                    confidence: 0.91
                ),
            ],
            quality: .calibrated
        )
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion + Self.teamQuestion,
            environment: [:],
            model: ScriptedModel(answering: answers),
            stdout: &out,
            stderr: &err
        )

        // One code cannot carry two answers, so a batch exits 0 when decided.
        #expect(code == 0)
        #expect(out == "no\nreturns\n")
        #expect(err.isEmpty)
    }

    @Test("-q prints nothing and answers with the exit code")
    func quietVerdict() async {
        for (probability, expected) in [(0.8, Int32(0)), (0.2, Int32(1))] {
            var out = ""
            var err = ""

            let code = await Decide.run(
                arguments: Self.spamQuestion + ["-q"],
                environment: [:],
                model: Self.spamModel(probability: probability),
                stdout: &out,
                stderr: &err
            )

            #expect(code == expected, "P(yes) \(probability)")
            #expect(out.isEmpty, "P(yes) \(probability)")
            #expect(err.isEmpty, "P(yes) \(probability)")
        }
    }

    @Test("A yes/no answer below its bar exits 2 and prints nothing")
    func unsureVerdict() async {
        var out = ""
        var err = ""

        // P(yes) 0.8 is confidence 0.60, below the bar of 0.90.
        let code = await Decide.run(
            arguments: Self.spamQuestion + ["--min-confidence", "0.9"],
            environment: [:],
            model: Self.spamModel(probability: 0.8),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 2)
        #expect(out.isEmpty)
        #expect(
            err == """
                Error: unsure: question 1 ("Is this message spam?") has confidence 0.60, \
                below the bar of 0.90

                """
        )
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

    @Test("--version prints the version on stdout and exits 0")
    func version() async {
        let model = Self.triageModel()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--version"],
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == Decide.version + "\n")
        #expect(err.isEmpty)
        #expect(model.callCount == 0)
    }

    @Test("--version with other arguments prints the version on stderr and exits 10")
    func versionWithArguments() async {
        let model = Self.triageModel()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--version", "--context", "c"],
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(out.isEmpty)
        #expect(err == Decide.version + "\nError: --version takes no other arguments\n")
        #expect(model.callCount == 0)
    }

    @Test("The usage text shows the version and lists --version")
    func usageShowsVersion() {
        #expect(Decide.usage.hasPrefix("decide " + Decide.version + "\n\n"))
        #expect(Decide.usage.contains("  --version "))
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
