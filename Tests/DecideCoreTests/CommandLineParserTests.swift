import Testing

@testable import DecideCore

@Suite("CommandLineParser")
struct CommandLineParserTests {
    @Test("The README classification example parses")
    func classificationExample() throws {
        let result = try CommandLineParser.parse([
            "--context", "@ticket.txt",
            "Which team handles this ticket?",
            "--option", "shipping",
            "--option", "billing",
            "--option", "returns",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .file("ticket.txt"),
                        questions: [
                            Question(
                                instructions: "Which team handles this ticket?",
                                options: [
                                    Option(id: "shipping"),
                                    Option(id: "billing"),
                                    Option(id: "returns"),
                                ]
                            )
                        ]
                    )
                )
        )
    }

    @Test("The batch example keeps each question's own options, in order")
    func batchExample() throws {
        let result = try CommandLineParser.parse([
            "--context", "@ticket.txt",
            "Which team handles this ticket?",
            "--option", "shipping",
            "--option", "billing",
            "--option", "returns",
            "How urgent is this ticket?",
            "--option", "not_urgent",
            "--option", "somewhat_urgent",
            "--option", "urgent",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .file("ticket.txt"),
                        questions: [
                            Question(
                                instructions: "Which team handles this ticket?",
                                options: [
                                    Option(id: "shipping"),
                                    Option(id: "billing"),
                                    Option(id: "returns"),
                                ]
                            ),
                            Question(
                                instructions: "How urgent is this ticket?",
                                options: [
                                    Option(id: "not_urgent"),
                                    Option(id: "somewhat_urgent"),
                                    Option(id: "urgent"),
                                ]
                            ),
                        ]
                    )
                )
        )
    }

    @Test("--context=@path names a file")
    func contextEqualsFile() throws {
        let result = try CommandLineParser.parse(["--context=@ticket.txt", "Q", "--option", "a"])
        #expect(result == .run(Invocation(context: .file("ticket.txt"), questions: [question])))
    }

    @Test("--context takes text with spaces verbatim")
    func contextText() throws {
        let result = try CommandLineParser.parse(["--context", "text with spaces", "Q", "--option", "a"])
        #expect(result == .run(Invocation(context: .text("text with spaces"), questions: [question])))
    }

    @Test("--context= with nothing after the = is empty text")
    func contextEqualsEmpty() throws {
        let result = try CommandLineParser.parse(["--context=", "Q", "--option", "a"])
        #expect(result == .run(Invocation(context: .text(""), questions: [question])))
    }

    @Test("An @ after the first character stays literal text")
    func contextLateAtSign() throws {
        let result = try CommandLineParser.parse(["--context", "mail me@example.com", "Q", "--option", "a"])
        #expect(result == .run(Invocation(context: .text("mail me@example.com"), questions: [question])))
    }

    @Test("--option id=desc splits at the first =")
    func optionDescription() throws {
        let result = try CommandLineParser.parse(["--context", "c", "Q", "--option", "id=desc"])
        #expect(result == .run(invocation(Option(id: "id", description: "desc"))))
    }

    @Test("--option id=a=b keeps the rest of the value as the description")
    func optionDescriptionWithEquals() throws {
        let result = try CommandLineParser.parse(["--context", "c", "Q", "--option", "id=a=b"])
        #expect(result == .run(invocation(Option(id: "id", description: "a=b"))))
    }

    @Test("--option=id=desc works too")
    func optionEqualsForm() throws {
        let result = try CommandLineParser.parse(["--context", "c", "Q", "--option=id=desc"])
        #expect(result == .run(invocation(Option(id: "id", description: "desc"))))
    }

    @Test("An empty description counts as none")
    func optionEmptyDescription() throws {
        let result = try CommandLineParser.parse(["--context", "c", "Q", "--option", "a="])
        #expect(result == .run(invocation(Option(id: "a", description: nil))))
    }

    @Test("--help wins wherever it appears")
    func helpAnywhere() throws {
        #expect(try CommandLineParser.parse(["--help", "--context", "c"]) == .help)
        #expect(try CommandLineParser.parse(["--context", "c", "--help", "Q"]) == .help)
        #expect(try CommandLineParser.parse(["--context", "c", "Q", "--help"]) == .help)
        #expect(try CommandLineParser.parse(["-h"]) == .help)
        #expect(try CommandLineParser.parse(["--bogus", "--help"]) == .help)
    }

    @Test("An empty argument list is an error")
    func noArguments() {
        #expect(throws: UsageError("no arguments given")) {
            try CommandLineParser.parse([])
        }
    }

    @Test("A line with no --context is an error")
    func noContext() {
        #expect(throws: UsageError("no --context given")) {
            try CommandLineParser.parse(["Q", "--option", "a"])
        }
    }

    @Test("A second --context is an error")
    func twoContexts() {
        #expect(throws: UsageError("--context was given twice")) {
            try CommandLineParser.parse(["--context", "one", "--context", "two", "Q", "--option", "a"])
        }
    }

    @Test("--context @ names no file")
    func contextBareAtSign() {
        #expect(throws: UsageError("--context @ names no file")) {
            try CommandLineParser.parse(["--context", "@", "Q", "--option", "a"])
        }
    }

    @Test("A line with no question is an error")
    func noQuestion() {
        #expect(throws: UsageError("no question given")) {
            try CommandLineParser.parse(["--context", "c"])
        }
    }

    @Test("--option before any question is an error")
    func optionBeforeQuestion() {
        #expect(throws: UsageError("--option before any question")) {
            try CommandLineParser.parse(["--context", "c", "--option", "a", "Q"])
        }
    }

    @Test("A question with no --option is an error that names it")
    func questionWithoutOptions() {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q1", "--option", "a", "Q2"])
        }
        #expect(error?.message == "question 2 (\"Q2\") has no --option")
    }

    @Test("A repeated option id is an error that names the id")
    func duplicateOptionIDs() {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q1", "--option", "a", "--option", "a"])
        }
        #expect(error?.message == "question 1 (\"Q1\") repeats the option \"a\"")
    }

    @Test("An unknown flag is an error that names the token")
    func unknownFlag() {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "--bogus", "Q", "--option", "a"])
        }
        #expect(error?.message.contains("--bogus") == true)

        let lone = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "-", "--option", "a"])
        }
        #expect(lone?.message == "unknown flag: -")
    }

    @Test("--context as the last token needs a value")
    func contextWithoutValue() {
        #expect(throws: UsageError("--context needs a value")) {
            try CommandLineParser.parse(["Q", "--option", "a", "--context"])
        }
    }

    @Test("--option as the last token needs a value")
    func optionWithoutValue() {
        #expect(throws: UsageError("--option needs a value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--option"])
        }
    }

    @Test("An empty question token is an error that names its number")
    func emptyQuestion() {
        #expect(throws: UsageError("question 2 is empty")) {
            try CommandLineParser.parse(["--context", "c", "Q1", "--option", "a", ""])
        }
    }

    @Test("An --option with no id is an error")
    func optionWithoutID() {
        #expect(throws: UsageError("an --option has no id")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--option", ""])
        }
        #expect(throws: UsageError("an --option has no id")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--option", "=desc"])
        }
    }

    /// One question with one option, for the tests that check the context.
    private let question = Question(instructions: "Q", options: [Option(id: "a")])

    /// One question that holds `option`, for the tests that check an option.
    private func invocation(_ option: Option) -> Invocation {
        Invocation(context: .text("c"), questions: [Question(instructions: "Q", options: [option])])
    }
}
