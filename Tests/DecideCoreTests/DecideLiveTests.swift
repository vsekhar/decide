import Foundation
import Testing

@testable import DecideCore

/// Tests that call the real service. Requests are cheap; round trips are
/// not, so each test here proves something a scripted model cannot.
///
/// Run it with the model and the key in the environment:
///
/// ```sh
/// set -a; . ./.env; set +a; swift test --filter DecideLive
/// ```
///
/// Without them this test fails. It never skips, because a green run that
/// talked to nothing says nothing.
@Suite("DecideLive", .serialized)
struct DecideLiveTests {
    /// The real environment, or a recorded failure that names what is missing.
    ///
    /// The key may come from `DECIDE_MODEL_API_KEY` or from a provider's own
    /// variable, as the tool allows.
    private func liveEnvironment(
        _ location: SourceLocation = #_sourceLocation
    ) -> [String: String]? {
        let environment = ProcessInfo.processInfo.environment
        func isSet(_ variable: String) -> Bool {
            let value = environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return !(value?.isEmpty ?? true)
        }
        let keyVariables = [ModelConfiguration.apiKeyVariable, "TYPESAFE_API_KEY", "OPENROUTER_API_KEY"]
        let missing: String? =
            if !isSet(ModelConfiguration.modelVariable) {
                ModelConfiguration.modelVariable
            } else if !keyVariables.contains(where: isSet) {
                keyVariables.joined(separator: ", ")
            } else {
                nil
            }
        guard let missing else { return environment }
        Issue.record(
            """
            \(missing) is not set, so the live test cannot reach the service. \
            Run: set -a; . ./.env; set +a; swift test --filter DecideLive
            """,
            sourceLocation: location
        )
        return nil
    }

    @Test("decide answers a three-question batch about a support ticket")
    func triagesATicket() async {
        guard let environment = liveEnvironment() else { return }

        let ticket = """
            I sent the shoes back two weeks ago and I still have not got my money back. \
            Order 4471.
            """
        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: [
                "--context", ticket,
                "Which team handles this ticket?",
                "--option", "shipping", "--option", "billing", "--option", "returns",
                "How urgent is this ticket?",
                "--level", "not_urgent", "--level", "somewhat_urgent", "--level", "urgent",
                "Should we issue a refund?",
                "--yes", "Yes", "--no", "No",
            ],
            environment: environment,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(err.isEmpty)
        // One line per question, in question order.
        let lines = out.split(separator: "\n").map(String.init)
        #expect(out.hasSuffix("\n"))
        #expect(lines.count == 3)
        guard lines.count == 3 else { return }
        #expect(["shipping", "billing", "returns"].contains(lines[0]))
        #expect(["not_urgent", "somewhat_urgent", "urgent"].contains(lines[1]))
        #expect(["Yes", "No"].contains(lines[2]))
    }

    @Test("decide answers the README refund example from two named contexts")
    func refundFromNamedContexts() async {
        guard let environment = liveEnvironment() else { return }

        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: [
                "--context", "refund_policy=Refunds are allowed within 30 days of delivery.",
                "--context",
                "ticket=I received the shoes five days ago and want my money back. Order 4471.",
                "Should we issue a refund?",
                "--yes", "yes=Allowed by refund_policy and requested in ticket",
                "--no", "no",
            ],
            environment: environment,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "yes\n")
        #expect(err.isEmpty)
    }

    @Test("decide answers a question with no context")
    func answersWithoutContext() async {
        guard let environment = liveEnvironment() else { return }

        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["Is Atlanta the capital of Georgia?"],
            environment: environment,
            stdout: &out,
            stderr: &err
        )

        #expect(code == 0)
        #expect(out == "yes\n")
        #expect(err.isEmpty)
    }

    @Test("A --api-key on the line reaches the provider")
    func keyFlagReachesTheProvider() async {
        guard let environment = liveEnvironment() else { return }

        var out = ""
        var err = ""

        let code = await Decide.run(
            arguments: ["--api-key", "not-a-key", "Is Atlanta the capital of Georgia?"],
            environment: environment,
            stdout: &out,
            stderr: &err
        )

        // The real key is in the environment, so only a flag the provider
        // saw can make this fail.
        #expect(code == 10)
        #expect(err == "Error: the model server rejected the API key.\n")
        #expect(out.isEmpty)
    }
}
