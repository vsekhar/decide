import Testing

@testable import DecideCore

@Suite("Invocation")
struct InvocationTests {
    @Test("A --model replaces the model the environment names")
    func modelOverTheEnvironment() {
        let run = invocation(model: "openrouter:a/b", apiKey: nil)

        let environment = run.applied(
            to: [ModelConfiguration.modelVariable: "typesafe:jev-latest", "X": "1"]
        )

        #expect(environment == [ModelConfiguration.modelVariable: "openrouter:a/b", "X": "1"])
    }

    @Test("An --api-key replaces the key the environment names")
    func keyOverTheEnvironment() {
        let run = invocation(model: nil, apiKey: "new")

        let environment = run.applied(
            to: [ModelConfiguration.apiKeyVariable: "old", "X": "1"]
        )

        #expect(environment == [ModelConfiguration.apiKeyVariable: "new", "X": "1"])
    }

    @Test("A flag the line leaves out leaves its variable alone")
    func aFlagLeftOutChangesNothing() {
        let before = [
            ModelConfiguration.modelVariable: "typesafe:jev-latest",
            ModelConfiguration.apiKeyVariable: "old",
        ]

        let keyOnly = invocation(model: nil, apiKey: "new").applied(to: before)
        let modelOnly = invocation(model: "openrouter:a/b", apiKey: nil).applied(to: before)

        #expect(keyOnly == [
            ModelConfiguration.modelVariable: "typesafe:jev-latest",
            ModelConfiguration.apiKeyVariable: "new",
        ])
        #expect(modelOnly == [
            ModelConfiguration.modelVariable: "openrouter:a/b",
            ModelConfiguration.apiKeyVariable: "old",
        ])
    }

    @Test("Both flags land together and every other variable passes through")
    func bothFlagsLand() {
        let run = invocation(model: "a:b", apiKey: "k")

        let environment = run.applied(to: ["X": "1"])

        #expect(environment == [
            ModelConfiguration.modelVariable: "a:b",
            ModelConfiguration.apiKeyVariable: "k",
            "X": "1",
        ])
    }

    @Test("A flag lands when the variable is not set")
    func aFlagSetsAnUnsetVariable() {
        let run = invocation(model: "a:b", apiKey: nil)

        let environment = run.applied(to: [:])

        #expect(environment == [ModelConfiguration.modelVariable: "a:b"])
    }

    @Test("Neither flag leaves the environment as it was")
    func neitherFlagChangesAnything() {
        let before = ["A": "1", "B": "2", "C": "3"]

        let environment = invocation(model: nil, apiKey: nil).applied(to: before)

        #expect(environment == before)
    }

    /// One run of one yes/no question, with the model and key a line gave.
    private func invocation(model: String?, apiKey: String?) -> Invocation {
        Invocation(
            context: nil,
            questions: [
                Question(
                    instructions: "Q",
                    kind: .verdict(yes: Option(id: "yes"), no: Option(id: "no"))
                )
            ],
            model: model,
            apiKey: apiKey
        )
    }
}
