import Testing

@testable import DecideCore

@Suite("Unsure")
struct UnsureTests {
    /// The refund question below its bar, as question 3 of a run.
    static let refund = Unsure(
        number: 3,
        instructions: "Should we issue a refund?",
        confidence: 0.2,
        minimumConfidence: 0.7
    )

    @Test("One unsure question gives its number, text, confidence, and bar")
    func oneQuestion() {
        #expect(
            Unsure.report([Self.refund])
                == """
                Unsure: question 3 ("Should we issue a refund?") has confidence 0.20, \
                below the bar of 0.70
                """
        )
    }

    @Test("Two unsure questions share one line, in order, joined by a semicolon")
    func twoQuestions() {
        let urgency = Unsure(
            number: 4,
            instructions: "Is this urgent?",
            confidence: 0.4,
            minimumConfidence: 0.5
        )
        #expect(
            Unsure.report([Self.refund, urgency])
                == """
                Unsure: question 3 ("Should we issue a refund?") has confidence 0.20, \
                below the bar of 0.70; question 4 ("Is this urgent?") has confidence 0.40, \
                below the bar of 0.50
                """
        )
    }

    @Test("A newline in the question prints as a space, so the report is one line")
    func newlineInQuestion() {
        let question = Unsure(
            number: 1,
            instructions: "Should we\nissue a refund?",
            confidence: 0.2,
            minimumConfidence: 0.7
        )
        #expect(
            Unsure.report([question])
                == """
                Unsure: question 1 ("Should we issue a refund?") has confidence 0.20, \
                below the bar of 0.70
                """
        )
    }
}
