import Testing

@testable import DecideCore

/// The file every test names, so each error proves it carries the path.
private let path = "/tmp/x/triage.json"

/// Decodes text as the file at `path`.
private func decode(_ text: String) throws -> [Question] {
    try JSONQuestionFile.questions(from: text, path: path)
}

/// The error the file must throw. Line 0: a JSON file names a path, not a line.
private func failure(_ problem: String) -> ConfigError {
    ConfigError(path: path, line: 0, problem: problem)
}

/// The syntax refusal, with the detail Foundation gives on this platform.
/// Apple's Foundation reports a byte offset, or "Unexpected end of file";
/// the open-source Foundation on Linux reports neither, so the message
/// there is the bare "not valid JSON". Both hold no text from the file.
private func notValidJSON(_ detail: String) -> ConfigError {
    #if canImport(Darwin)
    return failure("not valid JSON" + detail)
    #else
    return failure("not valid JSON")
    #endif
}

/// A file of one question, the object's keys given as JSON text.
private func file(_ question: String) -> String {
    #"{"questions": [{\#(question)}]}"#
}

/// The README's `triage.json`, byte for byte.
private let triage = """
    {
      "questions": [
        {
          "name": "team",
          "instructions": "Which team handles this ticket?",
          "options": [
            {
              "id": "shipping",
              "summary": "Delivery issues",
              "examples": ["Package is late", "Tracking says delivered but nothing arrived"],
              "signals": ["Names a carrier or a tracking number"]
            },
            {
              "id": "billing",
              "summary": "Payment problems",
              "not_for": "Money back for an item the customer returned; that is returns",
              "examples": ["Charged twice", "Card declined at checkout"]
            },
            {
              "id": "returns",
              "summary": "Exchanges and refunds",
              "not_for": "Damage in transit; that is shipping",
              "examples": ["Wrong size", "Wants money back for a returned item"]
            }
          ]
        },
        {
          "name": "urgency",
          "instructions": "How urgent is this ticket?",
          "levels": [
            {"id": "not_urgent",      "summary": "Customer feedback or feature request"},
            {"id": "somewhat_urgent", "summary": "Customer problem, but customer not blocked"},
            {"id": "urgent",          "summary": "Customer blocked",
                                      "signals": ["cannot", "stuck", "deadline", "today"]}
          ]
        },
        {
          "name": "refund",
          "instructions": {
            "question": "Should we issue a refund?",
            "rules": [
              "Apply `refund_policy` to the `ticket`.",
              "When the policy is silent, answer no."
            ]
          },
          "yes": {"id": "Yes", "summary": "The policy allows a refund for this case"},
          "no":  {"id": "No",  "summary": "The policy forbids it, or the customer does not ask for money back"},
          "min-confidence": 0.7,
          "fallback": "No"
        }
      ]
    }
    """

@Suite("JSONQuestionFile")
struct JSONQuestionFileTests {
    @Test("The README's triage.json decodes to its three questions")
    func readmeFile() throws {
        let questions = try decode(triage)
        #expect(
            questions == [
                Question(
                    instructions: "Which team handles this ticket?",
                    kind: .choice([
                        Option(
                            id: "shipping",
                            description: "Delivery issues",
                            examples: [
                                "Package is late",
                                "Tracking says delivered but nothing arrived",
                            ],
                            signals: ["Names a carrier or a tracking number"]
                        ),
                        Option(
                            id: "billing",
                            description: "Payment problems",
                            notFor: "Money back for an item the customer returned; that is returns",
                            examples: ["Charged twice", "Card declined at checkout"]
                        ),
                        Option(
                            id: "returns",
                            description: "Exchanges and refunds",
                            notFor: "Damage in transit; that is shipping",
                            examples: ["Wrong size", "Wants money back for a returned item"]
                        ),
                    ]),
                    minimumConfidence: nil,
                    name: "team",
                    rules: [],
                    detail: .answer
                ),
                Question(
                    instructions: "How urgent is this ticket?",
                    kind: .rating([
                        Option(id: "not_urgent", description: "Customer feedback or feature request"),
                        Option(
                            id: "somewhat_urgent",
                            description: "Customer problem, but customer not blocked"
                        ),
                        Option(
                            id: "urgent",
                            description: "Customer blocked",
                            signals: ["cannot", "stuck", "deadline", "today"]
                        ),
                    ]),
                    minimumConfidence: nil,
                    name: "urgency",
                    rules: [],
                    detail: .answer
                ),
                Question(
                    instructions: "Should we issue a refund?",
                    kind: .verdict(
                        yes: Option(
                            id: "Yes",
                            description: "The policy allows a refund for this case"
                        ),
                        no: Option(
                            id: "No",
                            description:
                                "The policy forbids it, or the customer does not ask for money back"
                        )
                    ),
                    minimumConfidence: 0.7,
                    fallback: "No",
                    name: "refund",
                    rules: [
                        "Apply `refund_policy` to the `ticket`.",
                        "When the policy is silent, answer no.",
                    ],
                    detail: .answer
                ),
            ]
        )
    }

    @Test("String instructions make a yes/no question with the default sides")
    func stringInstructions() throws {
        let questions = try decode(file(#""instructions": "Is this spam?""#))
        #expect(
            questions == [
                Question(
                    instructions: "Is this spam?",
                    kind: .verdict(yes: Option(id: "yes"), no: Option(id: "no"))
                )
            ]
        )
    }

    @Test("stats true shows the stats")
    func stats() throws {
        let questions = try decode(file(#""instructions": "Is this spam?", "stats": true"#))
        #expect(questions.map(\.detail) == [.stats])
    }

    @Test("distribution true shows the distribution")
    func distribution() throws {
        let questions = try decode(file(#""instructions": "Is this spam?", "distribution": true"#))
        #expect(questions.map(\.detail) == [.distribution])
    }

    @Test("stats and distribution together show the distribution")
    func statsAndDistribution() throws {
        let questions = try decode(
            file(#""instructions": "Is this spam?", "stats": true, "distribution": true"#)
        )
        #expect(questions.map(\.detail) == [.distribution])
    }

    @Test("A stats value that is not a boolean is refused")
    func statsNotBoolean() {
        #expect(throws: failure("questions[0].stats: expected true or false")) {
            try decode(file(#""instructions": "Is this spam?", "stats": "yes""#))
        }
    }

    @Test("A question with no instructions is refused")
    func missingInstructions() {
        #expect(throws: failure(#"questions[0]: missing key "instructions""#)) {
            try decode(file(#""name": "spam""#))
        }
    }

    @Test("An unknown top-level key is refused")
    func unknownTopLevelKey() {
        #expect(throws: failure(#"unknown key "version""#)) {
            try decode(#"{"version": 1, "questions": [{"instructions": "Is this spam?"}]}"#)
        }
    }

    @Test("A top-level array is refused")
    func topLevelArray() {
        #expect(throws: failure("a question file is an object with a questions array")) {
            try decode(#"[{"instructions": "Is this spam?"}]"#)
        }
    }

    @Test("An empty questions array is refused")
    func emptyQuestions() {
        #expect(throws: failure("questions: a question file needs at least one question")) {
            try decode(#"{"questions": []}"#)
        }
    }

    @Test("An unknown question key is refused")
    func unknownQuestionKey() {
        #expect(throws: failure(#"questions[0]: unknown key "question""#)) {
            try decode(file(#""question": "Is this spam?""#))
        }
    }

    @Test("A typo in an option key is refused")
    func optionKeyTypo() {
        let text = file(
            #"""
            "instructions": "Which team?",
            "options": [{"id": "a"}, {"id": "b"}, {"id": "c", "sumary": "C"}]
            """#
        )
        #expect(throws: failure(#"questions[0].options[2]: unknown key "sumary""#)) {
            try decode(text)
        }
    }

    @Test("Options with levels are refused")
    func optionsWithLevels() {
        let text = file(
            #"""
            "instructions": "Which team?",
            "options": [{"id": "a"}],
            "levels": [{"id": "low"}, {"id": "high"}]
            """#
        )
        #expect(throws: failure("questions[0]: question 1 mixes options, levels, yes, or no")) {
            try decode(text)
        }
    }

    @Test("Options with yes are refused")
    func optionsWithYes() {
        let text = file(
            #""instructions": "Which team?", "options": [{"id": "a"}], "yes": {"id": "y"}"#
        )
        #expect(throws: failure("questions[0]: question 1 mixes options, levels, yes, or no")) {
            try decode(text)
        }
    }

    @Test("A rating with one level is refused")
    func oneLevel() {
        #expect(throws: failure("questions[0].levels: a rating needs at least two levels")) {
            try decode(file(#""instructions": "How urgent?", "levels": [{"id": "low"}]"#))
        }
    }

    @Test("A choice with no options is refused")
    func zeroOptions() {
        #expect(throws: failure("questions[0].options: a choice needs at least one option")) {
            try decode(file(#""instructions": "Which team?", "options": []"#))
        }
    }

    @Test("A repeated option id is refused")
    func repeatedOption() {
        let text = file(#""instructions": "Which team?", "options": [{"id": "a"}, {"id": "a"}]"#)
        #expect(throws: failure(#"questions[0].options[1].id: question 1 repeats the option "a""#)) {
            try decode(text)
        }
    }

    @Test("Yes and no with one id are refused")
    func sameSides() {
        let text = file(#""instructions": "Is this spam?", "yes": {"id": "x"}, "no": {"id": "x"}"#)
        #expect(throws: failure("questions[0]: question 1 uses the same value for yes and no")) {
            try decode(text)
        }
    }

    @Test("A name that is not an identifier is refused", arguments: ["1st", "a-b", ""])
    func badName(name: String) {
        let problem = "questions[0].name: not a valid name: a letter or _ then letters, digits, or _"
        #expect(throws: failure(problem)) {
            try decode(file(#""instructions": "Is this spam?", "name": "\#(name)""#))
        }
    }

    @Test("A name two questions share is refused")
    func repeatedName() {
        let text = #"""
            {"questions": [
                {"instructions": "Which team?", "name": "team", "options": [{"id": "a"}]},
                {"instructions": "Is this spam?", "name": "team"}
            ]}
            """#
        #expect(throws: failure(#"questions[1].name: question name "team" is used twice"#)) {
            try decode(text)
        }
    }

    @Test("A min-confidence above 1 is refused")
    func confidenceAboveOne() {
        let problem = "questions[0].min-confidence: expected a number from 0 to 1"
        #expect(throws: failure(problem)) {
            try decode(file(#""instructions": "Is this spam?", "min-confidence": 1.5"#))
        }
    }

    @Test("A min-confidence that is a string is refused")
    func confidenceString() {
        let problem = "questions[0].min-confidence: expected a number from 0 to 1"
        #expect(throws: failure(problem)) {
            try decode(file(#""instructions": "Is this spam?", "min-confidence": "0.7""#))
        }
    }

    @Test("fallback sets the question's fallback")
    func fallback() throws {
        let questions = try decode(
            file(#""instructions": "Which team?", "options": [{"id": "a"}], "fallback": "human""#)
        )
        #expect(questions.map(\.fallback) == ["human"])
    }

    @Test("An empty fallback is refused")
    func emptyFallback() {
        #expect(throws: failure("questions[0].fallback: is empty")) {
            try decode(file(#""instructions": "Which team?", "options": [{"id": "a"}], "fallback": """#))
        }
    }

    @Test("A fallback holding a tab or a newline is refused", arguments: [#"a\tb"#, #"a\nb"#, #"a\rb"#])
    func breakingFallback(value: String) {
        let text = file(#""instructions": "Which team?", "options": [{"id": "a"}], "fallback": "\#(value)""#)
        #expect(throws: failure("questions[0].fallback: holds a tab or a newline")) {
            try decode(text)
        }
    }

    @Test("A yes/no fallback that is neither side's value is refused")
    func fallbackNotASide() throws {
        let sides = #""instructions": "Is this spam?", "yes": {"id": "spam"}, "no": {"id": "ham"}"#
        #expect(try decode(file(sides + #", "fallback": "ham""#)).map(\.fallback) == ["ham"])
        #expect(throws: failure("questions[0].fallback: is not the yes or no value")) {
            try decode(file(sides + #", "fallback": "no""#))
        }
        #expect(throws: failure("questions[0].fallback: is not the yes or no value")) {
            try decode(file(#""instructions": "Is this spam?", "fallback": "maybe""#))
        }
    }

    @Test("A fallback that is not a string is refused")
    func fallbackNotString() {
        #expect(throws: failure("questions[0].fallback: expected a string")) {
            try decode(file(#""instructions": "Which team?", "options": [{"id": "a"}], "fallback": 1"#))
        }
    }

    @Test("A side with only examples is refused for its missing id")
    func sideWithoutId() {
        #expect(throws: failure(#"questions[0].yes: missing key "id""#)) {
            try decode(file(#""instructions": "Is this spam?", "yes": {"examples": ["Buy now"]}"#))
        }
    }

    @Test(
        "An id holding =, a tab, or a newline is refused",
        arguments: [#"a=b"#, #"a\tb"#, #"a\nb"#, #"a\rb"#]
    )
    func breakingId(id: String) {
        let text = file(#""instructions": "Which team?", "options": [{"id": "x"}, {"id": "\#(id)"}]"#)
        #expect(throws: failure("questions[0].options[1].id: holds =, a tab, or a newline")) {
            try decode(text)
        }
    }

    @Test("Invalid JSON is refused with the offset and no file content")
    func invalidJSON() {
        #expect(throws: notValidJSON(" at byte offset 14")) {
            try decode(#"{"questions": secret}"#)
        }
    }

    @Test("An empty text is refused")
    func emptyText() {
        #expect(throws: notValidJSON(": Unexpected end of file")) {
            try decode("")
        }
    }
    @Test("A bad escape in string instructions is refused with the offset")
    func instructionsBadEscape() {
        #expect(throws: notValidJSON(" at byte offset 35")) {
            try decode(#"{"questions": [{"instructions": "x\q"}]}"#)
        }
    }

    @Test("A literal tab in string instructions is refused with the offset")
    func instructionsLiteralTab() {
        #expect(throws: notValidJSON(" at byte offset 34")) {
            try decode("{\"questions\": [{\"instructions\": \"x\ty\"}]}")
        }
    }

    @Test("Null instructions are refused")
    func nullInstructions() {
        #expect(throws: failure("questions[0].instructions: expected a string or an object")) {
            try decode(file(#""instructions": null"#))
        }
    }

    @Test("A min-confidence too large for a Double is refused", arguments: ["1e999", "-1e999"])
    func confidenceOverflow(bar: String) {
        let problem = "questions[0].min-confidence: expected a number from 0 to 1"
        #expect(throws: failure(problem)) {
            try decode(file(#""instructions": "Is this spam?", "min-confidence": \#(bar)"#))
        }
    }

    @Test("A bad escape in a summary is refused with the offset")
    func summaryBadEscape() {
        #expect(throws: notValidJSON(" at byte offset 85")) {
            try decode(
                #"{"questions": [{"instructions": "Which team?", "options": [{"id": "a", "summary": "x\q"}]}]}"#
            )
        }
    }

    @Test("An empty id is refused")
    func emptyId() {
        #expect(throws: failure("questions[0].options[0].id: is empty")) {
            try decode(file(#""instructions": "Which team?", "options": [{"id": ""}]"#))
        }
    }

    @Test("A top-level scalar or null is refused", arguments: ["1", #""questions""#, "null"])
    func topLevelScalar(text: String) {
        #expect(throws: failure("a question file is an object with a questions array")) {
            try decode(text)
        }
    }

    @Test("An unknown key in the instructions object is refused")
    func unknownInstructionsKey() {
        #expect(throws: failure(#"questions[0].instructions: unknown key "rule""#)) {
            try decode(file(#""instructions": {"question": "Is this spam?", "rule": ["a"]}"#))
        }
    }

    @Test("An instructions object with no question is refused")
    func instructionsWithoutQuestion() {
        #expect(throws: failure(#"questions[0].instructions: missing key "question""#)) {
            try decode(file(#""instructions": {"rules": ["a"]}"#))
        }
    }

    @Test("Rules that are a string are refused")
    func rulesString() {
        let problem = "questions[0].instructions.rules: expected an array of strings"
        #expect(throws: failure(problem)) {
            try decode(file(#""instructions": {"question": "Is this spam?", "rules": "a"}"#))
        }
    }

    @Test("Rules holding a number are refused")
    func rulesNumber() {
        let problem = "questions[0].instructions.rules: expected an array of strings"
        #expect(throws: failure(problem)) {
            try decode(file(#""instructions": {"question": "Is this spam?", "rules": ["a", 1]}"#))
        }
    }

    @Test("Levels with yes are refused")
    func levelsWithYes() {
        let text = file(
            #""instructions": "How urgent?", "levels": [{"id": "low"}, {"id": "high"}], "yes": {"id": "y"}"#
        )
        #expect(throws: failure("questions[0]: question 1 mixes options, levels, yes, or no")) {
            try decode(text)
        }
    }

    @Test("A file with no questions key is refused")
    func missingQuestions() {
        #expect(throws: failure(#"missing key "questions""#)) {
            try decode("{}")
        }
    }

    @Test("Examples that are not an array of strings are refused")
    func examplesWrongType() {
        let problem = "questions[0].options[0].examples: expected an array of strings"
        #expect(throws: failure(problem)) {
            try decode(file(#""instructions": "Which team?", "options": [{"id": "a", "examples": "x"}]"#))
        }
    }

    @Test("Signals that are not an array of strings are refused")
    func signalsWrongType() {
        let problem = "questions[0].yes.signals: expected an array of strings"
        #expect(throws: failure(problem)) {
            try decode(file(#""instructions": "Is this spam?", "yes": {"id": "y", "signals": [true]}"#))
        }
    }

    @Test("A distribution value that is not a boolean is refused")
    func distributionNotBoolean() {
        #expect(throws: failure("questions[0].distribution: expected true or false")) {
            try decode(file(#""instructions": "Is this spam?", "distribution": 1"#))
        }
    }

    @Test("Only a yes side leaves no as its default")
    func onlyYes() throws {
        let questions = try decode(
            file(#""instructions": "Is this spam?", "yes": {"id": "spam", "summary": "Junk"}"#)
        )
        #expect(
            questions == [
                Question(
                    instructions: "Is this spam?",
                    kind: .verdict(
                        yes: Option(id: "spam", description: "Junk"),
                        no: Option(id: "no")
                    )
                )
            ]
        )
    }

    @Test("A min-confidence of 0 or 1 is accepted", arguments: [0.0, 1.0])
    func confidenceBounds(bar: Double) throws {
        let questions = try decode(
            file(#""instructions": "Is this spam?", "min-confidence": \#(Int(bar))"#)
        )
        #expect(questions.map(\.minimumConfidence) == [bar])
    }
}
