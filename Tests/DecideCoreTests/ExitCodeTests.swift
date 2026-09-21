import DecisionModels
import Testing

@testable import DecideCore

/// Stands in for a transport failure the provider wraps.
private struct SomeError: Error {}

/// An error the mapping has never seen.
private struct Unknown: Error {}

/// Every error the CLI can meet, with the exit code it must give.
private func errorTable() -> [(error: any Error, code: Int32)] {
    [
        (DecisionError.unavailable(.notConfigured("TYPESAFE_API_KEY")), 10),
        (DecisionError.unavailable(.offline), 11),
        (DecisionError.unavailable(.deviceNotEligible), 11),
        (DecisionError.unavailable(.modelNotReady), 11),
        (DecisionError.unavailable(.other("x")), 11),
        (DecisionError.unsupported(.repeatedSamples), 10),
        (DecisionError.unsupported(.structuredCriteria), 10),
        (DecisionError.unsupported(.structuredInstructions), 10),
        (DecisionError.unsupported(.tooManyOptions(id: "q1", count: 300, limit: 255)), 10),
        (DecisionError.unsupported(.tooManyLevels(id: "q1", count: 11, limit: 10)), 10),
        (DecisionError.unsupported(.tooManyQuestions(count: 5, limit: 4)), 10),
        (DecisionError.invalidQuestion(id: "q1", reason: "r"), 10),
        (DecisionError.contextSizeExceeded(limit: 1, estimated: 2), 10),
        (DecisionError.contextSizeExceeded(limit: nil, estimated: nil), 10),
        (DecisionError.rateLimited(retryAfter: .seconds(2)), 11),
        (DecisionError.rateLimited(retryAfter: nil), 11),
        (DecisionError.overloaded, 11),
        (DecisionError.unauthorized, 10),
        (DecisionError.timeout, 11),
        (DecisionError.refused, 11),
        (DecisionError.guardrailViolation, 11),
        (DecisionError.insufficientProbabilityQuality(got: .pointEstimate, required: .calibrated), 11),
        (DecisionError.malformedResponse("bad"), 11),
        (DecisionError.malformedResponse("line one\r\nline two"), 11),
        (DecisionError.malformedResponse("line one\u{2028}line two"), 11),
        (DecisionError.transport(SomeError()), 11),
        (UsageError("x"), 10),
        (ConfigurationError.missingModel, 10),
        (ConfigurationError.malformedModel("jev-latest"), 10),
        (ConfigurationError.unknownProvider("foo"), 10),
        (CancellationError(), 11),
        (Unknown(), 11),
        (
            UnsureError(questions: [
                Unsure(
                    number: 3,
                    instructions: "Should we issue a refund?",
                    confidence: 0.2,
                    minimumConfidence: 0.7
                )
            ]),
            2
        ),
    ]
}

@Suite("ExitCode")
struct ExitCodeTests {
    @Test("Every error maps to its exit code")
    func codes() {
        for (error, expected) in errorTable() {
            #expect(ExitCode.code(for: error) == expected, "\(error)")
        }
    }

    @Test("The constants are the README's numbers")
    func constants() {
        #expect(ExitCode.decided == 0)
        #expect(ExitCode.no == 1)
        #expect(ExitCode.unsure == 2)
        #expect(ExitCode.setup == 10)
        #expect(ExitCode.remote == 11)
    }

    @Test("No error lands in the range reserved for decision-like states")
    func reservedRange() {
        for (error, _) in errorTable() {
            let code = ExitCode.code(for: error)
            #expect(
                code == 0 || code == 2 || code >= 10,
                "1 is no, 2 is unsure, and 3 to 9 are reserved: \(error)"
            )
        }
    }

    @Test("Every message is one line and starts with Error:")
    func messageShape() {
        // Checked scalar by scalar: a CRLF is one Character, so a search for
        // "\n" in a String would miss it.
        let breaks: Set<Unicode.Scalar> = [
            "\n", "\r", "\u{0B}", "\u{0C}", "\u{85}", "\u{2028}", "\u{2029}",
        ]
        for (error, _) in errorTable() {
            let message = ExitCode.message(for: error)
            #expect(message.hasPrefix("Error: "), "\(error)")
            #expect(!message.unicodeScalars.contains { breaks.contains($0) }, "\(error)")
        }
    }

    @Test("A transport failure uses the README's wording")
    func transportMessage() {
        #expect(
            ExitCode.message(for: DecisionError.transport(SomeError()))
                == "Error: cannot reach decision model server"
        )
    }

    @Test("A missing model names the variable and both examples")
    func missingModelMessage() {
        let message = ExitCode.message(for: ConfigurationError.missingModel)
        #expect(message.contains("DECIDE_MODEL"))
        #expect(message.contains("typesafe:jev-latest"))
        #expect(message.contains("openrouter:typesafe/jev-1.13"))
    }

    @Test("A usage error keeps its message and gains the prefix")
    func usageMessage() {
        #expect(
            ExitCode.message(for: UsageError("no --context given"))
                == "Error: no --context given"
        )
    }

    @Test("An unsure run names every question, its confidence, and its bar")
    func unsureMessage() {
        let one = UnsureError(questions: [
            Unsure(
                number: 3,
                instructions: "Should we issue a refund?",
                confidence: 0.2,
                minimumConfidence: 0.7
            )
        ])
        #expect(
            ExitCode.message(for: one)
                == """
                Error: unsure: question 3 ("Should we issue a refund?") has confidence 0.20, \
                below the bar of 0.70
                """
        )

        let two = UnsureError(questions: one.questions + [
            Unsure(
                number: 4,
                instructions: "Is this urgent?",
                confidence: 0.4,
                minimumConfidence: 0.5
            )
        ])
        #expect(
            ExitCode.message(for: two)
                == """
                Error: unsure: question 3 ("Should we issue a refund?") has confidence 0.20, \
                below the bar of 0.70; question 4 ("Is this urgent?") has confidence 0.40, \
                below the bar of 0.50
                """
        )
    }

    @Test("A newline in a payload does not break the line")
    func payloadNewline() {
        let message = ExitCode.message(for: DecisionError.malformedResponse("line one\nline two"))
        #expect(!message.contains("\n"))
    }
}
