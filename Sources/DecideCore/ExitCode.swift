import DecisionModels
import Foundation

/// The README's exit codes and the one-line message for each error.
///
/// 0 is a decision, and yes when the run has one yes/no question; 1 is no
/// in that case; 2 is unsure. 3 to 9 are reserved for outcomes of the
/// question itself. Errors start at 10 and group by who has to act.
public enum ExitCode {
    /// The run produced a decision.
    public static let decided: Int32 = 0
    /// The one yes/no question answered no.
    public static let no: Int32 = 1
    /// The model answered, but below the bar a question set.
    public static let unsure: Int32 = 2
    /// Setup or input error: something local must change. Bad usage, a
    /// missing or malformed model or key, a rejected key, an unreadable
    /// file, or a question the model cannot take.
    public static let setup: Int32 = 10
    /// Remote error: try again later, or blame the server.
    public static let remote: Int32 = 11

    /// Gives the exit code for an error.
    public static func code(for error: any Error) -> Int32 {
        switch error {
        case is UsageError:
            setup
        case is ConfigurationError:
            setup
        case is UnsureError:
            unsure
        case let error as DecisionError:
            code(for: error)
        default:
            remote
        }
    }

    /// Gives the one-line message for an error. It never holds a key.
    public static func message(for error: any Error) -> String {
        switch error {
        case let error as UsageError:
            oneLine("Error: \(error.message)")
        case let error as ConfigurationError:
            oneLine(message(for: error))
        case let error as DecisionError:
            oneLine(message(for: error))
        case let error as UnsureError:
            oneLine(message(for: error))
        case is CancellationError:
            "Error: the run was cancelled."
        default:
            oneLine("Error: \(String(describing: error))")
        }
    }

    private static func code(for error: DecisionError) -> Int32 {
        switch error {
        case .unavailable(.notConfigured), .unauthorized, .invalidQuestion, .unsupported,
            .contextSizeExceeded:
            setup
        case .unavailable, .rateLimited, .overloaded, .timeout, .refused, .guardrailViolation,
            .insufficientProbabilityQuality, .malformedResponse, .transport:
            remote
        @unknown default:
            remote
        }
    }

    private static func message(for error: ConfigurationError) -> String {
        switch error {
        case .missingModel:
            """
            Error: \(ModelConfiguration.modelVariable) is not set. Use provider:model, \
            for example typesafe:jev-latest or openrouter:typesafe/jev-1.13.
            """
        case .malformedModel(let value):
            """
            Error: \(ModelConfiguration.modelVariable) "\(value)" is not provider:model. \
            Use for example typesafe:jev-latest or openrouter:typesafe/jev-1.13.
            """
        case .unknownProvider(let name):
            """
            Error: \(ModelConfiguration.modelVariable) names an unknown provider "\(name)". \
            Providers: \(providerList).
            """
        }
    }

    private static func message(for error: DecisionError) -> String {
        switch error {
        case .unavailable(let reason):
            message(for: reason)
        case .unsupported(let what):
            "Error: the model cannot take this request: \(detail(for: what))."
        case .invalidQuestion(let id, let reason):
            "Error: invalid question \(id): \(reason)"
        case .contextSizeExceeded(let limit, let estimated):
            if let limit, let estimated {
                "Error: the context is too large for the model. "
                    + "About \(estimated) tokens, the limit is \(limit)."
            } else {
                "Error: the context is too large for the model."
            }
        case .rateLimited(let retryAfter):
            if let retryAfter {
                "Error: the model server rate-limited the request. Retry in \(retryAfter)."
            } else {
                "Error: the model server rate-limited the request."
            }
        case .overloaded:
            "Error: the model server is overloaded."
        case .unauthorized:
            "Error: the model server rejected the API key."
        case .timeout:
            "Error: the request timed out."
        case .refused:
            "Error: the model declined to answer."
        case .guardrailViolation:
            "Error: the request tripped the model's safety filter."
        case .insufficientProbabilityQuality(let got, let required):
            "Error: the model's probability quality (\(got)) is below the required \(required)."
        case .malformedResponse(let what):
            "Error: the model's response is malformed: \(what)"
        case .transport:
            "Error: cannot reach decision model server"
        @unknown default:
            "Error: the model failed: \(error)"
        }
    }

    /// Names every unsure question with its confidence and its bar.
    private static func message(for error: UnsureError) -> String {
        let clauses = error.questions.map { question in
            "question \(question.number) (\"\(question.instructions)\") "
                + "has confidence \(String(format: "%.2f", question.confidence)), "
                + "below the bar of \(String(format: "%.2f", question.minimumConfidence))"
        }
        return "Error: unsure: " + clauses.joined(separator: "; ")
    }

    private static func message(for reason: DecisionModelAvailability.Reason) -> String {
        switch reason {
        case .notConfigured(let what):
            "Error: the model is not configured (\(what)). "
                + "Set \(ModelConfiguration.apiKeyVariable) or the provider's own key variable."
        case .offline:
            "Error: the model is offline."
        case .deviceNotEligible:
            "Error: this device cannot run the model."
        case .modelNotReady:
            "Error: the model is not ready yet."
        case .other(let what):
            "Error: the model is unavailable: \(what)"
        }
    }

    private static func detail(for what: DecisionError.Unsupported) -> String {
        switch what {
        case .structuredCriteria:
            "structured criteria"
        case .structuredInstructions:
            "structured instructions"
        case .tooManyOptions(let id, let count, let limit):
            "question \(id) has \(count) options, the limit is \(limit)"
        case .tooManyLevels(let id, let count, let limit):
            "question \(id) has \(count) levels, the limit is \(limit)"
        case .tooManyQuestions(let count, let limit):
            "\(count) questions, the limit is \(limit)"
        case .repeatedSamples:
            "repeated samples"
        @unknown default:
            "an unsupported feature"
        }
    }

    /// The providers a user can name, for the unknown provider message.
    private static var providerList: String {
        ModelConfiguration.Provider.allCases.map(\.rawValue).joined(separator: ", ")
    }

    /// Turns every line break into a space, so one error prints on one line.
    private static func oneLine(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar in
            CharacterSet.newlines.contains(scalar) ? " " : scalar
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
