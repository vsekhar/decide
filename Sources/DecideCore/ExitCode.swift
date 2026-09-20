import DecisionModels

/// The README's exit codes and the one-line message for each error.
public enum ExitCode {
    /// The run produced a decision.
    public static let decided: Int32 = 0
    /// Bad usage, or a missing model or key.
    public static let usage: Int32 = 2
    /// The run reached the model and failed.
    public static let runtime: Int32 = 3

    /// Gives the exit code for an error.
    public static func code(for error: any Error) -> Int32 {
        switch error {
        case is ConfigurationError:
            usage
        case let error as DecisionError:
            code(for: error)
        default:
            runtime
        }
    }

    /// Gives the one-line message for an error. It never holds a key.
    public static func message(for error: any Error) -> String {
        switch error {
        case let error as ConfigurationError:
            oneLine(message(for: error))
        case let error as DecisionError:
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
            usage
        case .unavailable, .rateLimited, .overloaded, .timeout, .refused, .guardrailViolation,
            .insufficientProbabilityQuality, .malformedResponse, .transport:
            runtime
        @unknown default:
            runtime
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

    /// Turns every newline into a space, so one error prints on one line.
    private static func oneLine(_ text: String) -> String {
        let scalars = text.unicodeScalars.map { scalar in
            scalar == "\n" || scalar == "\r" ? " " : scalar
        }
        return String(String.UnicodeScalarView(scalars))
    }
}
