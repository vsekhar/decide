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
        (DecisionError.unavailable(.notConfigured("TYPESAFE_API_KEY")), 2),
        (DecisionError.unavailable(.offline), 3),
        (DecisionError.unavailable(.deviceNotEligible), 3),
        (DecisionError.unavailable(.modelNotReady), 3),
        (DecisionError.unavailable(.other("x")), 3),
        (DecisionError.unsupported(.repeatedSamples), 2),
        (DecisionError.unsupported(.structuredCriteria), 2),
        (DecisionError.unsupported(.structuredInstructions), 2),
        (DecisionError.unsupported(.tooManyOptions(id: "q1", count: 300, limit: 255)), 2),
        (DecisionError.unsupported(.tooManyLevels(id: "q1", count: 11, limit: 10)), 2),
        (DecisionError.unsupported(.tooManyQuestions(count: 5, limit: 4)), 2),
        (DecisionError.invalidQuestion(id: "q1", reason: "r"), 2),
        (DecisionError.contextSizeExceeded(limit: 1, estimated: 2), 2),
        (DecisionError.contextSizeExceeded(limit: nil, estimated: nil), 2),
        (DecisionError.rateLimited(retryAfter: .seconds(2)), 3),
        (DecisionError.rateLimited(retryAfter: nil), 3),
        (DecisionError.overloaded, 3),
        (DecisionError.unauthorized, 2),
        (DecisionError.timeout, 3),
        (DecisionError.refused, 3),
        (DecisionError.guardrailViolation, 3),
        (DecisionError.insufficientProbabilityQuality(got: .pointEstimate, required: .calibrated), 3),
        (DecisionError.malformedResponse("bad"), 3),
        (DecisionError.malformedResponse("line one\r\nline two"), 3),
        (DecisionError.malformedResponse("line one\u{2028}line two"), 3),
        (DecisionError.transport(SomeError()), 3),
        (UsageError("x"), 2),
        (ConfigurationError.missingModel, 2),
        (ConfigurationError.malformedModel("jev-latest"), 2),
        (ConfigurationError.unknownProvider("foo"), 2),
        (CancellationError(), 3),
        (Unknown(), 3),
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

    @Test("A newline in a payload does not break the line")
    func payloadNewline() {
        let message = ExitCode.message(for: DecisionError.malformedResponse("line one\nline two"))
        #expect(!message.contains("\n"))
    }
}
