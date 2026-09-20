import DecisionModels
import Testing

@testable import DecideCore

@Suite("ModelConfiguration")
struct ModelConfigurationTests {
    @Test("typesafe:jev-latest builds the TypeSafe model")
    func typeSafeProvider() throws {
        let configuration = try ModelConfiguration(environment: ["DECIDE_MODEL": "typesafe:jev-latest"])
        #expect(configuration.provider == .typesafe)
        #expect(configuration.model == "jev-latest")
        #expect(configuration.apiKey == nil)
        #expect(
            configuration.makeModel().identity
                == DecisionModelIdentity(provider: "typesafe", name: "jev-latest")
        )
    }

    @Test("openrouter keeps the slash in the model part")
    func openRouterProvider() throws {
        let configuration = try ModelConfiguration(
            environment: ["DECIDE_MODEL": "openrouter:typesafe/jev-1.13"]
        )
        #expect(configuration.provider == .openrouter)
        #expect(configuration.model == "typesafe/jev-1.13")
        #expect(
            configuration.makeModel().identity
                == DecisionModelIdentity(provider: "openrouter", name: "typesafe/jev-1.13")
        )
    }

    @Test("A value without a colon is malformed")
    func noColon() {
        #expect(throws: ConfigurationError.malformedModel("jev-latest")) {
            try ModelConfiguration(environment: ["DECIDE_MODEL": "jev-latest"])
        }
    }

    @Test("An empty model part is malformed")
    func emptyModel() {
        #expect(throws: ConfigurationError.malformedModel("typesafe:")) {
            try ModelConfiguration(environment: ["DECIDE_MODEL": "typesafe:"])
        }
    }

    @Test("An empty provider part is malformed")
    func emptyProvider() {
        #expect(throws: ConfigurationError.malformedModel(":jev-latest")) {
            try ModelConfiguration(environment: ["DECIDE_MODEL": ":jev-latest"])
        }
    }

    @Test("Another provider name is unknown")
    func unknownProvider() {
        #expect(throws: ConfigurationError.unknownProvider("foo")) {
            try ModelConfiguration(environment: ["DECIDE_MODEL": "foo:bar"])
        }
    }

    @Test("An unset variable is missing")
    func unsetModel() {
        #expect(throws: ConfigurationError.missingModel) {
            try ModelConfiguration(environment: [:])
        }
    }

    @Test("A blank variable is missing")
    func blankModel() {
        #expect(throws: ConfigurationError.missingModel) {
            try ModelConfiguration(environment: ["DECIDE_MODEL": "   "])
        }
    }

    @Test("Surrounding whitespace goes")
    func paddedModel() throws {
        let configuration = try ModelConfiguration(
            environment: ["DECIDE_MODEL": " typesafe:jev-latest "]
        )
        #expect(configuration.provider == .typesafe)
        #expect(configuration.model == "jev-latest")
    }

    @Test("A blank key counts as unset")
    func blankKey() throws {
        let configuration = try ModelConfiguration(
            environment: ["DECIDE_MODEL": "typesafe:jev-latest", "DECIDE_MODEL_API_KEY": "   "]
        )
        #expect(configuration.apiKey == nil)
    }

    @Test("The key reaches the configuration")
    func key() throws {
        let configuration = try ModelConfiguration(
            environment: ["DECIDE_MODEL": "typesafe:jev-latest", "DECIDE_MODEL_API_KEY": "abc123"]
        )
        #expect(configuration.apiKey == "abc123")
    }

    @Test("A padded key is trimmed")
    func paddedKey() throws {
        let configuration = try ModelConfiguration(
            environment: ["DECIDE_MODEL": "typesafe:jev-latest", "DECIDE_MODEL_API_KEY": " abc123 "]
        )
        #expect(configuration.apiKey == "abc123")
    }
}
