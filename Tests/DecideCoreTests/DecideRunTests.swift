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
    /// The team question with the name `team`.
    private static let namedTeamQuestion = [
        "Which team handles this ticket?", "--name", "team",
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

    /// A model that answers one yes/no question, `q1`, at that P(yes), and
    /// keeps the request it got.
    private static func spamModel(
        probability: Double,
        recording box: RequestBox? = nil
    ) -> ScriptedModel {
        ScriptedModel { request in
            box?.record(request)
            return Answers(
                records: ["q1": .verdict(probability: probability)],
                quality: .calibrated
            )
        }
    }

    /// A model that answers the named team question under `team`, as a
    /// provider would, and keeps the request it got.
    private static func namedTeamModel(recording box: RequestBox? = nil) -> ScriptedModel {
        ScriptedModel { request in
            box?.record(request)
            return Answers(
                records: [
                    "team": .choice(
                        reported: "returns",
                        probabilities: ["returns": 0.91, "shipping": 0.06, "billing": 0.03],
                        confidence: 0.91
                    )
                ],
                quality: .calibrated
            )
        }
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

    @Test("The batch example with --show-names prints name=answer per line")
    func showNamesBatch() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion + Self.refundQuestion + ["--show-names"],
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "q1=returns\nq2=somewhat_urgent\nq3=Yes\n")
        #expect(err.isEmpty)
    }

    @Test("A yes/no question with --show-names keeps its exit code")
    func showNamesVerdict() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion + ["--show-names"],
            environment: [:],
            model: Self.spamModel(probability: 0.2),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 1)
        #expect(out == "q1=no\n")
        #expect(err.isEmpty)
    }

    @Test("An unsure run with --show-names prints nothing")
    func showNamesUnsure() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion + Self.refundQuestion(bar: "0.7") + ["--show-names"],
            environment: [:],
            model: Self.unsureRefundModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 2)
        #expect(out.isEmpty)
    }

    @Test("--show-names with -q exits 10 with the usage text")
    func showNamesWithQuiet() async {
        let model = Self.spamModel(probability: 0.8)
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion + ["--show-names", "-q"],
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.hasPrefix("Error: --show-names does not go with --quiet"))
        #expect(err.contains(Decide.usage))
        #expect(out.isEmpty)
        #expect(model.callCount == 0)
    }

    @Test("The usage text lists --show-names")
    func usageListsShowNames() {
        #expect(
            Decide.usage.contains("  --show-names                   Print each answer as name=answer")
        )
    }

    @Test("The batch example with --json prints one keyed line")
    func jsonBatch() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion + Self.refundQuestion + ["--json"],
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(
            out == """
                {"q1":{"kind":"choice","answer":"returns","confidence":0.91,\
                "probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}},\
                "q2":{"kind":"rating","answer":"somewhat_urgent","score":1.15,\
                "confidence":0.78,"probabilities":{"not_urgent":0.15,\
                "somewhat_urgent":0.55,"urgent":0.3}},\
                "q3":{"kind":"verdict","answer":"Yes","verdict":true,"confidence":0.74,\
                "probabilities":{"Yes":0.87,"No":0.13}}}

                """
        )
        #expect(err.isEmpty)
    }

    @Test("A yes/no question with --json keeps its exit code")
    func jsonVerdict() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion + ["--json"],
            environment: [:],
            model: Self.spamModel(probability: 0.2),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 1)
        #expect(
            out == """
                {"q1":{"kind":"verdict","answer":"no","verdict":false,"confidence":0.6,\
                "probabilities":{"yes":0.2,"no":0.8}}}

                """
        )
        #expect(err.isEmpty)
    }

    @Test("--json keys a named question by its name")
    func jsonNamedQuestion() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.namedTeamQuestion + ["--json"],
            environment: [:],
            model: Self.namedTeamModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(
            out == """
                {"team":{"kind":"choice","answer":"returns","confidence":0.91,\
                "probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}}}

                """
        )
        #expect(err.isEmpty)
    }

    @Test("An unsure run with --json prints nothing")
    func jsonUnsure() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.teamQuestion
                + Self.urgencyQuestion + Self.refundQuestion(bar: "0.7") + ["--json"],
            environment: [:],
            model: Self.unsureRefundModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 2)
        #expect(out.isEmpty)
    }

    @Test("--json with -q exits 10 with the usage text")
    func jsonWithQuiet() async {
        let model = Self.spamModel(probability: 0.8)
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: Self.spamQuestion + ["--json", "-q"],
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.hasPrefix("Error: --json does not go with --quiet"))
        #expect(err.contains(Decide.usage))
        #expect(out.isEmpty)
        #expect(model.callCount == 0)
    }

    @Test("The usage text lists --json")
    func usageListsJSON() {
        #expect(Decide.usage.contains("  --json                         Print one JSON object"))
    }

    @Test("A named question runs under its name")
    func namedQuestion() async {
        let box = RequestBox()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.namedTeamQuestion,
            environment: [:],
            model: Self.namedTeamModel(recording: box),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "returns\n")
        #expect(err.isEmpty)
        #expect(box.request?.questionnaire.specs.map(\.id) == ["team"])
    }

    @Test("A model that answers under q1 for a named question is a malformed response")
    func namedQuestionAnsweredByPosition() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.namedTeamQuestion,
            environment: [:],
            model: Self.triageModel(),
            stdout: &out,
            stderr: &err
        )

        let message = "Error: the model's response is malformed: "
            + "The response holds no answer for team.\n"
        #expect(code == 11)
        #expect(out.isEmpty)
        #expect(err == message)
    }

    @Test("Two questions with one name exit 10 with the usage text")
    func namesUsedTwice() async {
        let model = Self.spamModel(probability: 0.8)
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Q1", "--name", "team", "Q2", "--name", "team"],
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.hasPrefix("Error: question name \"team\" is used twice"))
        #expect(err.contains(Decide.usage))
        #expect(out.isEmpty)
        #expect(model.callCount == 0)
    }

    @Test("A name that equals another question's position id is refused by the library")
    func nameOfAnotherQuestionsPosition() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Q1", "--name", "q2", "--option", "a", "Q2", "--option", "b"],
            environment: [:],
            model: Self.spamModel(probability: 0.8),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(out.isEmpty)
        #expect(err == "Error: invalid question q2: Two questions share the id.\n")
    }

    @Test("--show-names prints a named question by its name")
    func showNamesNamedQuestion() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "some ticket text"] + Self.namedTeamQuestion
                + ["--show-names"],
            environment: [:],
            model: Self.namedTeamModel(),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "team=returns\n")
        #expect(err.isEmpty)
    }

    @Test("The usage text lists --name")
    func usageListsName() {
        #expect(Decide.usage.contains("  --name <name>                  The question's name"))
    }

    @Test("A question with no --context prints yes and exits 0")
    func noContextYes() async throws {
        let box = RequestBox()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?"],
            environment: [:],
            model: Self.spamModel(probability: 0.97, recording: box),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "yes\n")
        #expect(err.isEmpty)
        let request = try #require(box.request)
        #expect(request.state == nil)
    }

    @Test("-q with no --context prints nothing and exits 0")
    func noContextQuiet() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?", "-q"],
            environment: [:],
            model: Self.spamModel(probability: 0.97),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out.isEmpty)
        #expect(err.isEmpty)
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

    @Test("Two named @file contexts reach the model as one object")
    func namedFileContexts() async throws {
        let directory = FileManager.default.temporaryDirectory
        let ticketURL = directory.appendingPathComponent("\(UUID().uuidString).txt")
        let policyURL = directory.appendingPathComponent("\(UUID().uuidString).txt")
        let ticketText = "The parcel never arrived and I want my money back.\n"
        let policyText = "Refunds are allowed within 30 days of delivery.\n"
        try ticketText.write(to: ticketURL, atomically: true, encoding: .utf8)
        try policyText.write(to: policyURL, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: ticketURL)
            try? FileManager.default.removeItem(at: policyURL)
        }

        let box = RequestBox()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: [
                "--context", "ticket=@\(ticketURL.path)",
                "--context", "refund_policy=@\(policyURL.path)",
            ] + Self.teamQuestion,
            environment: [:],
            model: Self.triageModel(recording: box),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "returns\n")
        #expect(err.isEmpty)
        let request = try #require(box.request)
        #expect(
            request.state
                == .object(["ticket": .text(ticketText), "refund_policy": .text(policyText)])
        )
    }

    @Test("One named context reaches the model as a one-field object")
    func oneNamedContext() async throws {
        let box = RequestBox()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "ticket=some ticket text"] + Self.teamQuestion,
            environment: [:],
            model: Self.triageModel(recording: box),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "returns\n")
        #expect(err.isEmpty)
        let request = try #require(box.request)
        #expect(request.state == .object(["ticket": .text("some ticket text")]))
    }

    @Test("A missing named context file exits 10 and reaches no model")
    func missingNamedFile() async {
        let path = "/nonexistent/\(UUID().uuidString).txt"
        let model = Self.triageModel()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "ticket=@\(path)"] + Self.teamQuestion,
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

    @Test("A named and an unnamed context together exit 10 with the usage text")
    func mixedContexts() async {
        let model = Self.triageModel()
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--context", "ticket=t", "--context", "u"] + Self.teamQuestion,
            environment: [:],
            model: model,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(
            err.hasPrefix(
                """
                Error: every --context needs a name when there is more than one, \
                like --context ticket=@ticket.txt
                """
            )
        )
        #expect(err.contains(Decide.usage))
        #expect(out.isEmpty)
        #expect(model.callCount == 0)
    }

    @Test("The usage text lists the named context forms")
    func usageListsNamedContexts() {
        #expect(Decide.usage.contains("  --context <name>=<text> "))
        #expect(Decide.usage.contains("  --context <name>=@<path> "))
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

    @Test("A project config supplies the model")
    func modelFromProjectConfig() async throws {
        let tree = try ConfigTree(project: #"DECIDE_MODEL = "nosuch:model""#)
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        // The unknown provider proves the value came from the file, and that
        // no model was built and no request went out.
        #expect(code == 10)
        #expect(err.contains("nosuch"))
        #expect(out.isEmpty)
    }

    @Test("A malformed config exits 10 and names the file and line")
    func malformedProjectConfig() async throws {
        let tree = try ConfigTree(project: "DECIDE_MODEL = typesafe:jev-latest\n")
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("\(tree.projectFile):1:"))
        #expect(out.isEmpty)
    }

    @Test("The key in a project config exits 10 and names the file and line")
    func keyInProjectConfig() async throws {
        let tree = try ConfigTree(
            project: """
                DECIDE_MODEL = "typesafe:jev-latest"
                DECIDE_MODEL_API_KEY = "k"
                """
        )
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("\(tree.projectFile):2:"))
        #expect(err.contains("DECIDE_MODEL_API_KEY is allowed only in the home config"))
        #expect(out.isEmpty)
    }

    @Test("A home config carries the key and the run answers")
    func keyInHomeConfig() async throws {
        let tree = try ConfigTree(
            project: #"DECIDE_MODEL = "typesafe:jev-latest""#,
            home: #"DECIDE_MODEL_API_KEY = "k""#
        )
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            model: Self.spamModel(probability: 0.97),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "yes\n")
        #expect(err.isEmpty)
    }

    @Test("The environment wins over a project config")
    func environmentOverProjectConfig() async throws {
        let tree = try ConfigTree(project: #"DECIDE_MODEL = "nosuch:model""#)
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?"],
            environment: ["HOME": tree.home, "DECIDE_MODEL": "other:x"],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("other"))
        #expect(!err.contains("nosuch"))
        #expect(out.isEmpty)
    }

    @Test("Without a working directory no config file is read")
    func noWorkingDirectoryReadsNothing() async throws {
        // Both files name a model, so a run that read either would fail on
        // that provider, not on the unset variable.
        let tree = try ConfigTree(
            project: #"DECIDE_MODEL = "nosuch:model""#,
            home: """
                DECIDE_MODEL = "nohome:model"
                DECIDE_MODEL_API_KEY = "k"
                """
        )
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?"],
            environment: ["HOME": tree.home],
            currentDirectory: nil,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("DECIDE_MODEL is not set"))
        #expect(!err.contains("nosuch"))
        #expect(!err.contains("nohome"))
        #expect(out.isEmpty)
    }

    @Test("--model on the line beats DECIDE_MODEL")
    func modelFlagOverTheEnvironment() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--model", "nosuch:x", "Q?"],
            environment: ["DECIDE_MODEL": "other:model"],
            stdout: &out,
            stderr: &err
        )

        // Both values name an unknown provider, so neither path builds a
        // model or sends a request. The one the message names is the one
        // that won.
        #expect(code == 10)
        #expect(err.contains("nosuch"))
        #expect(!err.contains("other"))
        #expect(out.isEmpty)
    }

    @Test("--model on the line beats a project config")
    func modelFlagOverAProjectConfig() async throws {
        let tree = try ConfigTree(project: #"DECIDE_MODEL = "other:model""#)
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--model", "nosuch:x", "Q?"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("nosuch"))
        #expect(!err.contains("other"))
        #expect(out.isEmpty)
    }

    @Test("--model goes through the provider:model check")
    func modelFlagNeedsAProvider() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--model", "jev-latest", "Q?"],
            environment: [:],
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("is not provider:model"))
        #expect(out.isEmpty)
    }

    @Test("--model and --api-key do not disturb a scripted run")
    func modelAndKeyFlagsAnswer() async {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--model", "a:b", "--api-key", "k"] + Self.spamQuestion,
            environment: [:],
            model: Self.spamModel(probability: 0.8),
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "yes\n")
        #expect(err.isEmpty)
    }

    @Test("The usage text lists --model and --api-key as run flags")
    func usageListsTheRunFlags() {
        #expect(Decide.usage.contains("  --model <model>                The model for this run"))
        #expect(Decide.usage.contains("  --api-key <key>                The API key for this run"))
    }

    @Test("--set-config writes the home config, prints nothing, and exits 0")
    func setConfigWritesTheHomeFile() async throws {
        let tree = try ConfigTree()
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "typesafe:jev-latest"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out.isEmpty)
        #expect(err.isEmpty)
        let text = try String(contentsOfFile: tree.homeFile, encoding: .utf8)
        #expect(text == "DECIDE_MODEL = \"typesafe:jev-latest\"\n")
        #expect(tree.mode(tree.homeFile) == 0o600)
        #expect(tree.mode(tree.homeDirectory) == 0o700)
    }

    @Test("A set-config run reads no config chain")
    func setConfigReadsNoChain() async throws {
        // A broken project file up the tree stops a normal run; it must not
        // stop the write that would fix the home config.
        let tree = try ConfigTree(project: "DECIDE_MODEL = broken\n")
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "typesafe:jev-latest"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(err.isEmpty)
        #expect(FileManager.default.fileExists(atPath: tree.homeFile))
    }

    @Test("A write makes a permissive home config the owner's alone")
    func setConfigTightensTheMode() async throws {
        // The new file replaces the old one, so its mode is 0600 whatever
        // the old file's was.
        let tree = try ConfigTree(home: "# old\n")
        defer { tree.remove() }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: tree.homeFile
        )
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "typesafe:jev-latest"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        let text = try String(contentsOfFile: tree.homeFile, encoding: .utf8)
        #expect(text == "# old\nDECIDE_MODEL = \"typesafe:jev-latest\"\n")
        #expect(tree.mode(tree.homeFile) == 0o600)
    }

    @Test("A second --set-config changes only the model's line")
    func setConfigKeepsTheRestOfTheFile() async throws {
        let before = """
            # my settings
            DECIDE_MODEL = "typesafe:jev-latest"  # the one I use
            DECIDE_MODEL_API_KEY = "k"

            """
        let tree = try ConfigTree(home: before)
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "openrouter:typesafe/jev-1.13"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        let text = try String(contentsOfFile: tree.homeFile, encoding: .utf8)
        #expect(
            text == """
                # my settings
                DECIDE_MODEL = "openrouter:typesafe/jev-1.13"  # the one I use
                DECIDE_MODEL_API_KEY = "k"

                """
        )
    }

    @Test("--project writes the working directory's config")
    func setConfigWritesTheProjectFile() async throws {
        let tree = try ConfigTree()
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "typesafe:jev-latest", "--project"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(err.isEmpty)
        let text = try String(contentsOfFile: tree.sub + "/.decide/config", encoding: .utf8)
        #expect(text == "DECIDE_MODEL = \"typesafe:jev-latest\"\n")
        #expect(!FileManager.default.fileExists(atPath: tree.homeFile))
    }

    @Test("A key with a quote and a backslash reads back unchanged")
    func setConfigKeyReadsBack() async throws {
        let tree = try ConfigTree()
        defer { tree.remove() }
        let key = #"a"b\c"#
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--api-key", key],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        let config = try ConfigFiles.load(paths: ConfigPaths(project: [], home: [tree.homeFile])) {
            path in try? String(contentsOfFile: path, encoding: .utf8)
        }
        #expect(config[ModelConfiguration.apiKeyVariable] == key)
    }

    @Test("--api-key with --project exits 10 and writes nothing")
    func setConfigKeyToAProjectIsRefused() async throws {
        let tree = try ConfigTree()
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--api-key", "k", "--project"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("--api-key is allowed only in the home config"))
        #expect(out.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: tree.sub + "/.decide/config"))
        #expect(!FileManager.default.fileExists(atPath: tree.homeFile))
    }

    @Test("A malformed home config exits 10, names its line, and stays as it was")
    func setConfigOnAMalformedFile() async throws {
        let before = "DECIDE_MODEL = typesafe:jev-latest\n"
        let tree = try ConfigTree(home: before)
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "typesafe:jev-latest"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("\(tree.homeFile):1:"))
        #expect(out.isEmpty)
        #expect(try String(contentsOfFile: tree.homeFile, encoding: .utf8) == before)
    }

    @Test("A model that is not provider:model exits 10 and writes nothing")
    func setConfigRefusesABadModel() async throws {
        let tree = try ConfigTree()
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "jev-latest"],
            environment: ["HOME": tree.home],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("DECIDE_MODEL \"jev-latest\" is not provider:model"))
        #expect(out.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: tree.homeFile))
    }

    @Test("--set-config with no HOME exits 10")
    func setConfigWithoutHome() async throws {
        let tree = try ConfigTree()
        defer { tree.remove() }
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "typesafe:jev-latest"],
            environment: [:],
            currentDirectory: tree.sub,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("HOME is not set, so there is no home config"))
        #expect(out.isEmpty)
    }

    @Test("--project without a working directory exits 10")
    func setConfigProjectWithoutAWorkingDirectory() async throws {
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--set-config", "--model", "typesafe:jev-latest", "--project"],
            environment: [:],
            currentDirectory: nil,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 10)
        #expect(err.contains("--project has no working directory"))
        #expect(out.isEmpty)
    }
}

/// A temp tree for the config tests, so the lookup never leaves it.
///
/// `<tmp>/home` is HOME and `<tmp>/home/proj/sub` is the working directory.
/// A text becomes the file it belongs to; nil writes no file. `remove()`
/// takes the whole tree away.
private struct ConfigTree {
    /// The fake home directory.
    let home: String
    /// The working directory a run is given.
    let sub: String
    /// `<tmp>/home/proj/.decide/config`, written or not.
    let projectFile: String
    /// `<tmp>/home/.config/decide/config`, written or not.
    let homeFile: String

    private let root: URL

    init(project: String? = nil, home homeText: String? = nil) throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent("home")
        self.home = directory.path
        sub = directory.appendingPathComponent("proj/sub").path
        projectFile = directory.appendingPathComponent("proj/.decide/config").path
        homeFile = directory.appendingPathComponent(".config/decide/config").path
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: true)
        try write(project, to: projectFile)
        try write(homeText, to: homeFile)
    }

    /// The directory `homeFile` is in, `<tmp>/home/.config/decide`.
    var homeDirectory: String {
        URL(fileURLWithPath: homeFile).deletingLastPathComponent().path
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The permission bits of the file or directory at `path`, or nil when
    /// there is none.
    func mode(_ path: String) -> Int? {
        try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
    }

    private func write(_ text: String?, to path: String) throws {
        guard let text else { return }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
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
