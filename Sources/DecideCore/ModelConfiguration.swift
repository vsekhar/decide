import DecisionModels
import DecisionModelsOpenRouter
import DecisionModelsTypeSafe
import Foundation

/// What is wrong with DECIDE_MODEL.
public enum ConfigurationError: Error, Equatable, Sendable {
    /// The variable is unset or blank.
    case missingModel
    /// The value is not `provider:model`. The payload is the value.
    case malformedModel(String)
    /// No provider goes by that name. The payload is the name.
    case unknownProvider(String)
}

/// The model the environment names, and the key to use with it.
public struct ModelConfiguration: Equatable, Sendable {
    /// The variable that names the model.
    public static let modelVariable = "DECIDE_MODEL"
    /// The variable that carries the key.
    public static let apiKeyVariable = "DECIDE_MODEL_API_KEY"

    /// Who serves the model. The raw value is the part before the colon.
    public enum Provider: String, CaseIterable, Sendable {
        case typesafe
        case openrouter
    }

    /// Who serves the model.
    public let provider: Provider
    /// The part after the first colon, passed to the provider verbatim.
    public let model: String
    /// DECIDE_MODEL_API_KEY, or nil when unset or blank.
    public let apiKey: String?

    /// Reads the two variables.
    ///
    /// The value of DECIDE_MODEL is `provider:model`, split at the first
    /// colon. Surrounding whitespace goes. A blank key counts as unset.
    public init(environment: [String: String]) throws(ConfigurationError) {
        let raw = environment[Self.modelVariable]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = raw, !value.isEmpty else {
            throw .missingModel
        }
        guard let colon = value.firstIndex(of: ":") else {
            throw .malformedModel(value)
        }
        let providerName = String(value[value.startIndex..<colon])
        let model = String(value[value.index(after: colon)...])
        guard !providerName.isEmpty, !model.isEmpty else {
            throw .malformedModel(value)
        }
        guard let provider = Provider(rawValue: providerName) else {
            throw .unknownProvider(providerName)
        }
        let key = environment[Self.apiKeyVariable]?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.provider = provider
        self.model = model
        self.apiKey = (key?.isEmpty ?? true) ? nil : key
    }

    /// Builds the model this configuration names.
    ///
    /// Without a key here, each provider reads its own key variable.
    public func makeModel() -> any DecisionModel {
        switch provider {
        case .typesafe:
            Jev(version: model, apiKey: apiKey)
        case .openrouter:
            OpenRouterAlpha(model: model, apiKey: apiKey)
        }
    }
}
