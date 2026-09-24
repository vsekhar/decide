import Testing

@testable import DecideCore

@Suite("PlainOutput")
struct PlainOutputTests {
    /// The team question from the README, with its three options.
    static func teamQuestion(detail: Question.Detail = .answer, name: String? = nil) -> Question {
        Question(
            instructions: "Which team handles this ticket?",
            kind: .choice([Option(id: "shipping"), Option(id: "billing"), Option(id: "returns")]),
            name: name,
            detail: detail
        )
    }
    /// The urgency question from the README, with its three levels.
    static func urgencyQuestion(detail: Question.Detail = .answer) -> Question {
        Question(
            instructions: "How urgent is this ticket?",
            kind: .rating([
                Option(id: "not_urgent"), Option(id: "somewhat_urgent"), Option(id: "urgent"),
            ]),
            detail: detail
        )
    }
    /// The refund question from the README, with its two values.
    static func refundQuestion(detail: Question.Detail = .answer) -> Question {
        Question(
            instructions: "Should we issue a refund?",
            kind: .verdict(yes: Option(id: "Yes"), no: Option(id: "No")),
            detail: detail
        )
    }

    /// The team answer: returns, at the README's numbers.
    static let teamOutcome = Outcome(
        questionID: "q1",
        answer: "returns",
        confidence: 0.91,
        probabilities: ["returns": 0.91, "shipping": 0.06, "billing": 0.03]
    )
    /// The urgency answer: somewhat_urgent, with the model's score.
    static let urgencyOutcome = Outcome(
        questionID: "q2",
        answer: "somewhat_urgent",
        confidence: 0.78,
        probabilities: ["not_urgent": 0.15, "somewhat_urgent": 0.55, "urgent": 0.3],
        score: 1.2
    )
    /// The refund answer: Yes, at P(yes) 0.87.
    static let refundOutcome = Outcome(
        questionID: "q3",
        answer: "Yes",
        confidence: 0.74,
        probabilities: ["Yes": 0.87, "No": 0.13]
    )
    /// A refund answer of No, at P(yes) 0.13, so the same confidence.
    static let refusedOutcome = Outcome(
        questionID: "q3",
        answer: "No",
        confidence: 0.74,
        probabilities: ["Yes": 0.13, "No": 0.87]
    )

    @Test("A question with neither flag prints its answer alone")
    func answerAlone() {
        #expect(
            PlainOutput.line(for: Self.teamQuestion(), outcome: Self.teamOutcome) == "returns"
        )
        #expect(
            PlainOutput.line(for: Self.urgencyQuestion(), outcome: Self.urgencyOutcome)
                == "somewhat_urgent"
        )
        #expect(
            PlainOutput.line(for: Self.refundQuestion(), outcome: Self.refundOutcome) == "Yes"
        )
    }

    @Test("A named question prints name=answer")
    func namedAnswer() {
        let question = Self.teamQuestion(name: "team")
        #expect(PlainOutput.line(for: question, outcome: Self.teamOutcome) == "team=returns")
    }

    @Test("--stats adds the confidence and the answer's probability to a choice")
    func statsOnAChoice() {
        let question = Self.teamQuestion(detail: .stats)
        #expect(
            PlainOutput.line(for: question, outcome: Self.teamOutcome)
                == "returns\tconfidence:0.910 probability:0.910"
        )
    }

    @Test("--stats adds a rating's score after its probability")
    func statsOnARating() {
        let question = Self.urgencyQuestion(detail: .stats)
        #expect(
            PlainOutput.line(for: question, outcome: Self.urgencyOutcome)
                == "somewhat_urgent\tconfidence:0.780 probability:0.550 score:1.200"
        )
    }

    @Test("--stats on a no answer prints P(no) and no score")
    func statsOnAVerdict() {
        let question = Self.refundQuestion(detail: .stats)
        #expect(
            PlainOutput.line(for: question, outcome: Self.refusedOutcome)
                == "No\tconfidence:0.740 probability:0.870"
        )
    }

    @Test("--stats with a name keeps the head and adds one field")
    func statsWithAName() {
        let question = Self.teamQuestion(detail: .stats, name: "team")
        #expect(
            PlainOutput.line(for: question, outcome: Self.teamOutcome)
                == "team=returns\tconfidence:0.910 probability:0.910"
        )
    }

    @Test("--distribution adds one field per option, in declared order")
    func distributionOnAChoice() {
        let question = Self.teamQuestion(detail: .distribution, name: "team")
        #expect(
            PlainOutput.line(for: question, outcome: Self.teamOutcome)
                == "team=returns\tconfidence:0.910 probability:0.910"
                    + "\tshipping:0.060\tbilling:0.030\treturns:0.910"
        )
    }

    @Test("--distribution brackets each level with its index, counted from 0")
    func distributionOnARating() {
        let question = Self.urgencyQuestion(detail: .distribution)
        #expect(
            PlainOutput.line(for: question, outcome: Self.urgencyOutcome)
                == "somewhat_urgent\tconfidence:0.780 probability:0.550 score:1.200"
                    + "\tnot_urgent[0]:0.150\tsomewhat_urgent[1]:0.550\turgent[2]:0.300"
        )
    }

    @Test("--distribution puts a verdict's yes side first")
    func distributionOnAVerdict() {
        let question = Self.refundQuestion(detail: .distribution)
        #expect(
            PlainOutput.line(for: question, outcome: Self.refundOutcome)
                == "Yes\tconfidence:0.740 probability:0.870\tYes:0.870\tNo:0.130"
        )
    }

    @Test("A label with a space and one with a colon print as they are")
    func labelsWithSpacesAndColons() {
        let question = Question(
            instructions: "Should we issue a refund?",
            kind: .verdict(yes: Option(id: "Hell yeah"), no: Option(id: "no: forget it")),
            detail: .distribution
        )
        let outcome = Outcome(
            questionID: "q1",
            answer: "Hell yeah",
            confidence: 0.74,
            probabilities: ["Hell yeah": 0.87, "no: forget it": 0.13]
        )

        #expect(
            PlainOutput.line(for: question, outcome: outcome)
                == "Hell yeah\tconfidence:0.740 probability:0.870"
                    + "\tHell yeah:0.870\tno: forget it:0.130"
        )
    }

    @Test("An id the outcome does not hold reads 0.000")
    func missingID() {
        let question = Question(
            instructions: "Q",
            kind: .choice([Option(id: "a"), Option(id: "b")]),
            detail: .distribution
        )
        let outcome = Outcome(
            questionID: "q1", answer: "a", confidence: 0.5, probabilities: ["a": 1]
        )

        #expect(
            PlainOutput.line(for: question, outcome: outcome)
                == "a\tconfidence:0.500 probability:1.000\ta:1.000\tb:0.000"
        )
    }

    @Test("Every number takes three decimals, rounded")
    func rounding() {
        let question = Question(
            instructions: "Q",
            kind: .choice([Option(id: "a"), Option(id: "b"), Option(id: "c")]),
            detail: .distribution
        )
        let outcome = Outcome(
            questionID: "q1",
            answer: "a",
            confidence: 1,
            probabilities: ["a": 0.6666, "b": 1, "c": 0.0004]
        )

        #expect(
            PlainOutput.line(for: question, outcome: outcome)
                == "a\tconfidence:1.000 probability:0.667\ta:0.667\tb:1.000\tc:0.000"
        )
    }

    @Test("No line ends with a newline")
    func noTrailingNewline() {
        let lines = [
            PlainOutput.line(for: Self.teamQuestion(), outcome: Self.teamOutcome),
            PlainOutput.line(for: Self.urgencyQuestion(detail: .stats), outcome: Self.urgencyOutcome),
            PlainOutput.line(
                for: Self.refundQuestion(detail: .distribution), outcome: Self.refundOutcome
            ),
        ]
        for line in lines {
            #expect(!line.hasSuffix("\n"), "\(line)")
        }
    }
}
