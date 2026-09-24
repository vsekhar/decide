import Foundation
import Testing

@testable import DecideCore

@Suite("JSONOutput")
struct JSONOutputTests {
    /// The team question from the README, with its three options.
    static let teamQuestion = Question(
        instructions: "Which team handles this ticket?",
        kind: .choice([Option(id: "shipping"), Option(id: "billing"), Option(id: "returns")])
    )
    /// The urgency question from the README, with its three levels.
    static let urgencyQuestion = Question(
        instructions: "How urgent is this ticket?",
        kind: .rating([
            Option(id: "not_urgent"), Option(id: "somewhat_urgent"), Option(id: "urgent"),
        ])
    )
    /// The refund question from the README, with its two values.
    static let refundQuestion = Question(
        instructions: "Should we issue a refund?",
        kind: .verdict(yes: Option(id: "Yes"), no: Option(id: "No"))
    )

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

    @Test("A choice prints its kind, answer, confidence, and probabilities")
    func choice() {
        let line = JSONOutput.line(for: [Self.teamQuestion], outcomes: [Self.teamOutcome])
        #expect(
            line == """
                {"q1":{"kind":"choice","answer":"returns","confidence":0.91,\
                "probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}}}

                """
        )
    }

    @Test("A rating prints its score after the answer")
    func rating() {
        let line = JSONOutput.line(for: [Self.urgencyQuestion], outcomes: [Self.urgencyOutcome])
        #expect(
            line == """
                {"q2":{"kind":"rating","answer":"somewhat_urgent","score":1.2,"confidence":0.78,\
                "probabilities":{"not_urgent":0.15,"somewhat_urgent":0.55,"urgent":0.3}}}

                """
        )
    }

    @Test("A verdict prints its boolean after the answer")
    func verdict() {
        let line = JSONOutput.line(for: [Self.refundQuestion], outcomes: [Self.refundOutcome])
        #expect(
            line == """
                {"q3":{"kind":"verdict","answer":"Yes","verdict":true,"confidence":0.74,\
                "probabilities":{"Yes":0.87,"No":0.13}}}

                """
        )
    }

    @Test("Three named questions make the README's keyed line")
    func readmeExample() {
        let questions = [Self.teamQuestion, Self.urgencyQuestion, Self.refundQuestion]
        let outcomes = [
            Outcome(
                questionID: "team",
                answer: "returns",
                confidence: 0.91,
                probabilities: ["returns": 0.91, "shipping": 0.06, "billing": 0.03]
            ),
            Outcome(
                questionID: "urgency",
                answer: "somewhat_urgent",
                confidence: 0.78,
                probabilities: ["not_urgent": 0.15, "somewhat_urgent": 0.55, "urgent": 0.3],
                score: 1.2
            ),
            Outcome(
                questionID: "refund",
                answer: "Yes",
                confidence: 0.74,
                probabilities: ["Yes": 0.87, "No": 0.13]
            ),
        ]

        let line = JSONOutput.line(for: questions, outcomes: outcomes)

        #expect(
            line == """
                {"team":{"kind":"choice","answer":"returns","confidence":0.91,\
                "probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}},\
                "urgency":{"kind":"rating","answer":"somewhat_urgent","score":1.2,\
                "confidence":0.78,"probabilities":{"not_urgent":0.15,\
                "somewhat_urgent":0.55,"urgent":0.3}},\
                "refund":{"kind":"verdict","answer":"Yes","verdict":true,"confidence":0.74,\
                "probabilities":{"Yes":0.87,"No":0.13}}}

                """
        )
    }

    @Test("An id with a quote, a backslash, a newline, a control character, and é escapes")
    func escaping() throws {
        let id = "a\"b\\c\nd\u{1}/é"
        let question = Question(instructions: "Q", kind: .choice([Option(id: id)]))
        let outcome = Outcome(
            questionID: "q1", answer: id, confidence: 1.0, probabilities: [id: 1.0]
        )

        let line = JSONOutput.line(for: [question], outcomes: [outcome])

        #expect(
            line == """
                {"q1":{"kind":"choice","answer":"a\\"b\\\\c\\nd\\u0001/é","confidence":1.0,\
                "probabilities":{"a\\"b\\\\c\\nd\\u0001/é":1.0}}}

                """
        )
        // A slash stays as it is.
        #expect(!line.contains("\\/"))
        // The line is JSON a reader can parse, and the id comes back intact.
        let parsed = try #require(
            try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: [String: Any]]
        )
        #expect(parsed["q1"]?["answer"] as? String == id)
    }

    @Test("A verdict with custom labels keys its probabilities by them, yes first")
    func customVerdictLabels() {
        let question = Question(
            instructions: "Is this message spam?",
            kind: .verdict(yes: Option(id: "spam"), no: Option(id: "ham"))
        )
        let outcome = Outcome(
            questionID: "q1",
            answer: "spam",
            confidence: 0.8,
            probabilities: ["spam": 0.9, "ham": 0.1]
        )

        let line = JSONOutput.line(for: [question], outcomes: [outcome])

        #expect(line.contains("\"probabilities\":{\"spam\":0.9,\"ham\":0.1}"))
        #expect(line.contains("\"answer\":\"spam\""))
        #expect(line.contains("\"verdict\":true"))
    }

    @Test("A no answer prints the default labels and a false verdict")
    func defaultVerdictLabels() {
        let question = Question(
            instructions: "Is this message spam?",
            kind: .verdict(yes: Option(id: "yes"), no: Option(id: "no"))
        )
        let outcome = Outcome(
            questionID: "q1", answer: "no", confidence: 0.6, probabilities: ["yes": 0.2, "no": 0.8]
        )

        let line = JSONOutput.line(for: [question], outcomes: [outcome])

        #expect(
            line == """
                {"q1":{"kind":"verdict","answer":"no","verdict":false,"confidence":0.6,\
                "probabilities":{"yes":0.2,"no":0.8}}}

                """
        )
    }

    @Test("Probabilities come in the question's declared order, and an absent id is 0")
    func declaredOrder() {
        let question = Question(
            instructions: "Q",
            kind: .choice([Option(id: "a"), Option(id: "b"), Option(id: "c")])
        )
        let outcome = Outcome(
            questionID: "q1",
            answer: "c",
            confidence: 0.5,
            probabilities: ["c": 0.5, "a": 0.3, "b": 0.2]
        )

        let line = JSONOutput.line(for: [question], outcomes: [outcome])
        #expect(line.contains("\"probabilities\":{\"a\":0.3,\"b\":0.2,\"c\":0.5}"))

        let missing = Outcome(
            questionID: "q1", answer: "a", confidence: 0.5, probabilities: ["a": 0.5, "b": 0.5]
        )
        let second = JSONOutput.line(for: [question], outcomes: [missing])
        #expect(second.contains("\"probabilities\":{\"a\":0.5,\"b\":0.5,\"c\":0.0}"))
    }

    @Test("score is a rating's field alone, and verdict a verdict's")
    func kindFields() {
        let choice = JSONOutput.line(for: [Self.teamQuestion], outcomes: [Self.teamOutcome])
        #expect(!choice.contains("\"score\""))
        #expect(!choice.contains("\"verdict\""))

        let rating = JSONOutput.line(for: [Self.urgencyQuestion], outcomes: [Self.urgencyOutcome])
        #expect(rating.contains("\"score\""))
        #expect(!rating.contains("\"verdict\""))

        let verdict = JSONOutput.line(for: [Self.refundQuestion], outcomes: [Self.refundOutcome])
        #expect(verdict.contains("\"verdict\""))
        #expect(!verdict.contains("\"score\""))
    }

    /// The outcome as `Runner.decide` gives it for an answer below its bar:
    /// the same numbers, marked unsure.
    static func unsure(_ outcome: Outcome) -> Outcome {
        var outcome = outcome
        outcome.unsure = true
        return outcome
    }

    @Test("An unsure choice prints a null answer, then unsure, then the model's numbers")
    func unsureChoice() {
        let line = JSONOutput.line(
            for: [Self.teamQuestion], outcomes: [Self.unsure(Self.teamOutcome)]
        )
        #expect(
            line == """
                {"q1":{"kind":"choice","answer":null,"unsure":true,"confidence":0.91,\
                "probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}}}

                """
        )
    }

    @Test("An unsure rating prints unsure before its score")
    func unsureRating() {
        let line = JSONOutput.line(
            for: [Self.urgencyQuestion], outcomes: [Self.unsure(Self.urgencyOutcome)]
        )
        #expect(
            line == """
                {"q2":{"kind":"rating","answer":null,"unsure":true,"score":1.2,"confidence":0.78,\
                "probabilities":{"not_urgent":0.15,"somewhat_urgent":0.55,"urgent":0.3}}}

                """
        )
    }

    @Test("An unsure verdict prints a null answer and a null verdict")
    func unsureVerdict() {
        let line = JSONOutput.line(
            for: [Self.refundQuestion], outcomes: [Self.unsure(Self.refundOutcome)]
        )
        #expect(
            line == """
                {"q3":{"kind":"verdict","answer":null,"unsure":true,"verdict":null,\
                "confidence":0.74,"probabilities":{"Yes":0.87,"No":0.13}}}

                """
        )
    }

    @Test("A sure answer beside an unsure one prints no unsure key")
    func sureBesideUnsure() {
        let line = JSONOutput.line(
            for: [Self.teamQuestion, Self.refundQuestion],
            outcomes: [Self.teamOutcome, Self.unsure(Self.refundOutcome)]
        )
        #expect(
            line == """
                {"q1":{"kind":"choice","answer":"returns","confidence":0.91,\
                "probabilities":{"shipping":0.06,"billing":0.03,"returns":0.91}},\
                "q3":{"kind":"verdict","answer":null,"unsure":true,"verdict":null,\
                "confidence":0.74,"probabilities":{"Yes":0.87,"No":0.13}}}

                """
        )
    }

    @Test("The line ends with one newline")
    func oneNewline() {
        let line = JSONOutput.line(
            for: [Self.teamQuestion, Self.urgencyQuestion, Self.refundQuestion],
            outcomes: [Self.teamOutcome, Self.urgencyOutcome, Self.refundOutcome]
        )
        #expect(line.hasSuffix("\n"))
        #expect(!line.hasSuffix("\n\n"))
    }
}
