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
    /// What the scripted model answers: `q1` is the team, `q2` the urgency.
    private static let answers = Answers(
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
        ],
        quality: .calibrated
    )

    /// A model that gives those answers and keeps the request it got.
    private static func triageModel(recording box: RequestBox? = nil) -> ScriptedModel {
        ScriptedModel { request in
            box?.record(request)
            return Self.answers
        }
    }

    @Test("The batch example prints one answer per question, in order")
    func batchExample() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion,
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "returns\nsomewhat_urgent\n")
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
