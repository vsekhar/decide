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
                                kind: .choice([
                                    Option(id: "shipping"),
                                    Option(id: "billing"),
                                    Option(id: "returns"),
                                ])
                            )
                        ]
                    )
                )
        )
    }

    @Test("The README leveling example parses to a rating")
    func levelingExample() throws {
        let result = try CommandLineParser.parse([
            "--context", "@ticket.txt",
            "How urgent is this ticket?",
            "--level", "not_urgent",
            "--level", "somewhat_urgent",
            "--level", "urgent",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .file("ticket.txt"),
                        questions: [
                            Question(
                                instructions: "How urgent is this ticket?",
                                kind: .rating([
                                    Option(id: "not_urgent"),
                                    Option(id: "somewhat_urgent"),
                                    Option(id: "urgent"),
                                ])
                            )
                        ]
                    )
                )
        )
    }

    @Test("The README leveling example with descriptions parses")
    func describedLevelingExample() throws {
        let result = try CommandLineParser.parse([
            "--context", "@ticket.txt",
            "How urgent is this ticket?",
            "--level", "not_urgent=Customer feedback or feature request",
            "--level", "somewhat_urgent=Customer problem, but customer not blocked",
            "--level", "urgent=Customer blocked",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .file("ticket.txt"),
                        questions: [
                            Question(
                                instructions: "How urgent is this ticket?",
                                kind: .rating([
                                    Option(
                                        id: "not_urgent",
                                        description: "Customer feedback or feature request"
                                    ),
                                    Option(
                                        id: "somewhat_urgent",
                                        description: "Customer problem, but customer not blocked"
                                    ),
                                    Option(id: "urgent", description: "Customer blocked"),
                                ])
                            )
                        ]
                    )
                )
        )
    }

    @Test("The README yes or no example parses to a verdict")
    func verdictExample() throws {
        let result = try CommandLineParser.parse([
            "--context", "@ticket.txt",
            "Should we issue a refund?",
            "--yes", "Hell yeah",
            "--no", "Forget it",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .file("ticket.txt"),
                        questions: [
                            Question(
                                instructions: "Should we issue a refund?",
                                kind: .verdict(
                                    yes: Option(id: "Hell yeah"),
                                    no: Option(id: "Forget it")
                                )
                            )
                        ]
                    )
                )
        )
    }

    @Test("--yes Yes --no No parses to a verdict with those two values")
    func shortVerdictValues() throws {
        let result = try CommandLineParser.parse([
            "--context", "c", "Q", "--yes", "Yes", "--no", "No",
        ])
        #expect(result == .run(verdict(yes: Option(id: "Yes"), no: Option(id: "No"))))
    }

    @Test("--yes value=desc gives the description on the yes side")
    func verdictDescription() throws {
        let result = try CommandLineParser.parse([
            "--context", "c", "Q", "--yes", "Hell yeah=Allowed by the policy",
        ])
        #expect(
            result
                == .run(
                    verdict(
                        yes: Option(id: "Hell yeah", description: "Allowed by the policy"),
                        no: Option(id: "no")
                    )
                )
        )
    }

    @Test("A question with no kind flag is a yes/no question with the default values")
    func bareQuestion() throws {
        let result = try CommandLineParser.parse(["--context", "c", "Q"])
        #expect(result == .run(verdict(yes: Option(id: "yes"), no: Option(id: "no"))))
    }

    @Test("A side the user leaves out keeps its default value, in either order")
    func verdictDefaults() throws {
        #expect(
            try CommandLineParser.parse(["--context", "c", "Q", "--yes", "Yep"])
                == .run(verdict(yes: Option(id: "Yep"), no: Option(id: "no")))
        )
        #expect(
            try CommandLineParser.parse(["--context", "c", "Q", "--no", "Nope"])
                == .run(verdict(yes: Option(id: "yes"), no: Option(id: "Nope")))
        )
        #expect(
            try CommandLineParser.parse(["--context", "c", "Q", "--no", "Nope", "--yes", "Yep"])
                == .run(verdict(yes: Option(id: "Yep"), no: Option(id: "Nope")))
        )
    }

    @Test("The batch example keeps each question's own kind and values, in order")
    func batchExample() throws {
        let result = try CommandLineParser.parse([
            "--context", "@ticket.txt",
            "Which team handles this ticket?",
            "--option", "shipping",
            "--option", "billing",
            "--option", "returns",
            "How urgent is this ticket?",
            "--level", "not_urgent",
            "--level", "somewhat_urgent",
            "--level", "urgent",
            "Should we issue a refund?",
            "--min-confidence", "0.7",
            "--yes", "Yes",
            "--no", "No",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .file("ticket.txt"),
                        questions: [
                            Question(
                                instructions: "Which team handles this ticket?",
                                kind: .choice([
                                    Option(id: "shipping"),
                                    Option(id: "billing"),
                                    Option(id: "returns"),
                                ])
                            ),
                            Question(
                                instructions: "How urgent is this ticket?",
                                kind: .rating([
                                    Option(id: "not_urgent"),
                                    Option(id: "somewhat_urgent"),
                                    Option(id: "urgent"),
                                ])
                            ),
                            Question(
                                instructions: "Should we issue a refund?",
                                kind: .verdict(yes: Option(id: "Yes"), no: Option(id: "No")),
                                minimumConfidence: 0.7
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

    @Test("--level=id works too")
    func levelEqualsForm() throws {
        let result = try CommandLineParser.parse([
            "--context", "c", "Q", "--level=a", "--level=b=desc",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .text("c"),
                        questions: [
                            Question(
                                instructions: "Q",
                                kind: .rating([
                                    Option(id: "a"),
                                    Option(id: "b", description: "desc"),
                                ])
                            )
                        ]
                    )
                )
        )
    }

    @Test("--help wins wherever it appears")
    func helpAnywhere() throws {
        #expect(try CommandLineParser.parse(["--help", "--context", "c"]) == .help)
        #expect(try CommandLineParser.parse(["--context", "c", "--help", "Q"]) == .help)
        #expect(try CommandLineParser.parse(["--context", "c", "Q", "--help"]) == .help)
        #expect(try CommandLineParser.parse(["-h"]) == .help)
        #expect(try CommandLineParser.parse(["--bogus", "--help"]) == .help)
    }

    @Test("--version alone asks for the version")
    func version() throws {
        #expect(try CommandLineParser.parse(["--version"]) == .version(alone: true))
    }

    @Test("--version with anything else is the version, not alone")
    func versionAnywhere() throws {
        #expect(try CommandLineParser.parse(["--version", "--help"]) == .version(alone: false))
        #expect(try CommandLineParser.parse(["--help", "--version"]) == .version(alone: false))
        #expect(try CommandLineParser.parse(["--context", "c", "Q", "--version"]) == .version(alone: false))
        #expect(try CommandLineParser.parse(["--bogus", "--version"]) == .version(alone: false))
    }

    @Test("--version takes no value")
    func versionWithValue() {
        #expect(throws: UsageError("unknown flag: --version=1")) {
            try CommandLineParser.parse(["--version=1"])
        }
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

    @Test("--level before any question is an error")
    func levelBeforeQuestion() {
        #expect(throws: UsageError("--level before any question")) {
            try CommandLineParser.parse(["--context", "c", "--level", "a", "Q"])
        }
    }

    @Test("--yes before any question is an error")
    func yesBeforeQuestion() {
        #expect(throws: UsageError("--yes before any question")) {
            try CommandLineParser.parse(["--context", "c", "--yes", "y", "Q"])
        }
    }

    @Test("A question that mixes --option and --level is an error that names both flags")
    func mixedKinds() {
        let optionFirst = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q", "--option", "a", "--level", "b"])
        }
        #expect(optionFirst?.message == "question 1 (\"Q\") mixes --option and --level")

        let levelFirst = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q", "--level", "a", "--option", "b"])
        }
        #expect(levelFirst?.message == "question 1 (\"Q\") mixes --level and --option")
    }

    @Test("A question that mixes a verdict flag with another kind is an error")
    func mixedVerdictKinds() {
        let optionFirst = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q", "--option", "a", "--yes", "y"])
        }
        #expect(optionFirst?.message == "question 1 (\"Q\") mixes --option and --yes")

        let yesFirst = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q", "--yes", "y", "--level", "a"])
        }
        #expect(yesFirst?.message == "question 1 (\"Q\") mixes --yes and --level")
    }

    @Test("A repeated --yes or --no is an error that names the flag")
    func repeatedVerdictFlag() {
        let yes = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q", "--yes", "a", "--yes", "b"])
        }
        #expect(yes?.message == "question 1 (\"Q\") repeats --yes")

        let no = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q", "--no", "a", "--no", "b"])
        }
        #expect(no?.message == "question 1 (\"Q\") repeats --no")
    }

    @Test("The same value on both sides is an error that names the question")
    func sameValueBothSides() {
        let both = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q", "--yes", "same", "--no", "same"])
        }
        #expect(both?.message == "question 1 (\"Q\") uses the same value for --yes and --no")

        let againstDefault = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q", "--yes", "no"])
        }
        #expect(
            againstDefault?.message == "question 1 (\"Q\") uses the same value for --yes and --no"
        )
    }

    @Test("A rating with one level is an error that names the question")
    func oneLevel() {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q1", "--level", "a"])
        }
        #expect(error?.message == "question 1 (\"Q1\") needs at least two --level")
    }

    @Test("A repeated option id is an error that names the id")
    func duplicateOptionIDs() {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q1", "--option", "a", "--option", "a"])
        }
        #expect(error?.message == "question 1 (\"Q1\") repeats the option \"a\"")
    }

    @Test("A repeated level id is an error that names the id")
    func duplicateLevelIDs() {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["--context", "c", "Q1", "--level", "a", "--level", "a"])
        }
        #expect(error?.message == "question 1 (\"Q1\") repeats the level \"a\"")
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

    @Test("--level as the last token needs a value")
    func levelWithoutValue() {
        #expect(throws: UsageError("--level needs a value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--level"])
        }
    }

    @Test("--yes or --no as the last token needs a value")
    func verdictFlagWithoutValue() {
        #expect(throws: UsageError("--yes needs a value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--yes"])
        }
        #expect(throws: UsageError("--no needs a value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--no"])
        }
    }

    @Test("An empty level description counts as none")
    func levelEmptyDescription() throws {
        let result = try CommandLineParser.parse(["--context", "c", "Q", "--level", "a=", "--level", "b"])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .text("c"),
                        questions: [
                            Question(instructions: "Q", kind: .rating([Option(id: "a"), Option(id: "b")]))
                        ]
                    )
                )
        )
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

    @Test("A --level with no id is an error")
    func levelWithoutID() {
        #expect(throws: UsageError("a --level has no id")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--level", ""])
        }
        #expect(throws: UsageError("a --level has no id")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--level", "=desc"])
        }
    }

    @Test("A --yes or --no with no value is an error")
    func verdictFlagWithoutID() {
        #expect(throws: UsageError("a --yes has no value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--yes", ""])
        }
        #expect(throws: UsageError("a --yes has no value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--yes", "=desc"])
        }
        #expect(throws: UsageError("a --no has no value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--no", ""])
        }
        #expect(throws: UsageError("a --no has no value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--no", "=desc"])
        }
    }

    @Test("--min-confidence sets the bar, in either value form")
    func minimumConfidenceForms() throws {
        for tokens in [["--min-confidence", "0.7"], ["--min-confidence=0.7"]] {
            let result = try CommandLineParser.parse(
                ["--context", "c", "Q", "--yes", "Yes", "--no", "No"] + tokens
            )
            #expect(
                result
                    == .run(
                        Invocation(
                            context: .text("c"),
                            questions: [
                                Question(
                                    instructions: "Q",
                                    kind: .verdict(yes: Option(id: "Yes"), no: Option(id: "No")),
                                    minimumConfidence: 0.7
                                )
                            ]
                        )
                    )
            )
        }
    }

    @Test("--min-confidence works on a choice, a rating, and a verdict")
    func minimumConfidenceOnEveryKind() throws {
        let choice = try CommandLineParser.parse([
            "--context", "c", "Q", "--option", "a", "--option", "b", "--min-confidence", "0.5",
        ])
        #expect(bars(choice) == [0.5])

        let rating = try CommandLineParser.parse([
            "--context", "c", "Q", "--level", "a", "--level", "b", "--min-confidence", "0.5",
        ])
        #expect(bars(rating) == [0.5])

        let verdict = try CommandLineParser.parse([
            "--context", "c", "Q", "--yes", "Yes", "--no", "No", "--min-confidence", "0.5",
        ])
        #expect(bars(verdict) == [0.5])
    }

    @Test("--min-confidence before the kind flags leaves the kind to them")
    func minimumConfidenceBeforeKindFlags() throws {
        let result = try CommandLineParser.parse([
            "--context", "c", "Q", "--min-confidence", "0.5", "--option", "a", "--option", "b",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .text("c"),
                        questions: [
                            Question(
                                instructions: "Q",
                                kind: .choice([Option(id: "a"), Option(id: "b")]),
                                minimumConfidence: 0.5
                            )
                        ]
                    )
                )
        )
    }

    @Test("A question with no --min-confidence has no bar")
    func noMinimumConfidence() throws {
        let result = try CommandLineParser.parse(["--context", "c", "Q", "--option", "a"])
        #expect(bars(result) == [nil])
    }

    @Test("0 and 1 are bars")
    func minimumConfidenceEnds() throws {
        let zero = try CommandLineParser.parse(["--context", "c", "Q", "--min-confidence", "0"])
        #expect(bars(zero) == [0])

        let one = try CommandLineParser.parse(["--context", "c", "Q", "--min-confidence", "1"])
        #expect(bars(one) == [1])
    }

    @Test("A bar that is not a number from 0 to 1 is an error that quotes it")
    func minimumConfidenceOffTheRange() {
        for token in ["1.5", "-0.1", "abc", "nan", "inf", ""] {
            let error = #expect(throws: UsageError.self) {
                try CommandLineParser.parse(["--context", "c", "Q", "--min-confidence", token])
            }
            #expect(
                error?.message == "--min-confidence needs a number from 0 to 1, got \"\(token)\""
            )
        }
    }

    @Test("A repeated --min-confidence is an error that names the question")
    func repeatedMinimumConfidence() {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse([
                "--context", "c", "Q", "--min-confidence", "0.5", "--min-confidence", "0.7",
            ])
        }
        #expect(error?.message == "question 1 (\"Q\") repeats --min-confidence")
    }

    @Test("--min-confidence before any question is an error")
    func minimumConfidenceBeforeQuestion() {
        #expect(throws: UsageError("--min-confidence before any question")) {
            try CommandLineParser.parse(["--context", "c", "--min-confidence", "0.5", "Q"])
        }
    }

    @Test("--min-confidence as the last token needs a value")
    func minimumConfidenceWithoutValue() {
        #expect(throws: UsageError("--min-confidence needs a value")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--min-confidence"])
        }
    }

    @Test("--quiet and -q each drop the printed answer")
    func quietForms() throws {
        for token in ["--quiet", "-q"] {
            let result = try CommandLineParser.parse(["--context", "c", "Q", token])
            #expect(
                result
                    == .run(
                        verdict(yes: Option(id: "yes"), no: Option(id: "no"), quiet: true)
                    )
            )
        }
    }

    @Test("--quiet works wherever it appears")
    func quietAnywhere() throws {
        let expected = ParseResult.run(
            verdict(yes: Option(id: "Yes"), no: Option(id: "No"), quiet: true)
        )
        let question = ["Q", "--yes", "Yes", "--no", "No"]
        #expect(try CommandLineParser.parse(["--quiet", "--context", "c"] + question) == expected)
        #expect(try CommandLineParser.parse(["--context", "c", "--quiet"] + question) == expected)
        #expect(try CommandLineParser.parse(["--context", "c"] + question + ["--quiet"]) == expected)
    }

    @Test("A second --quiet is an error")
    func twoQuiets() {
        #expect(throws: UsageError("--quiet was given twice")) {
            try CommandLineParser.parse(["--context", "c", "Q", "--quiet", "-q"])
        }
    }

    @Test("--quiet on anything but one yes/no question is an error")
    func quietNeedsOneVerdict() {
        let lines = [
            ["--context", "c", "Q", "--option", "a", "--option", "b", "--quiet"],
            ["--context", "c", "Q", "--level", "a", "--level", "b", "--quiet"],
            ["--context", "c", "Q1", "--quiet", "Q2", "--option", "a"],
        ]
        for line in lines {
            #expect(throws: UsageError("--quiet needs exactly one yes/no question"), "\(line)") {
                try CommandLineParser.parse(line)
            }
        }
    }

    @Test("--option -q makes an option with that id and leaves the run loud")
    func quietAsAnOptionValue() throws {
        let result = try CommandLineParser.parse(["--context", "c", "Q", "--option", "-q"])
        #expect(result == .run(invocation(Option(id: "-q"))))
    }

    /// The bar on every question a parse produced, in question order.
    private func bars(_ result: ParseResult) -> [Double?] {
        guard case .run(let invocation) = result else {
            Issue.record("Expected a run, got \(result).")
            return []
        }
        return invocation.questions.map(\.minimumConfidence)
    }

    /// One question with one option, for the tests that check the context.
    private let question = Question(instructions: "Q", kind: .choice([Option(id: "a")]))

    /// One question that holds `option`, for the tests that check an option.
    private func invocation(_ option: Option) -> Invocation {
        Invocation(
            context: .text("c"),
            questions: [Question(instructions: "Q", kind: .choice([option]))]
        )
    }

    /// One yes/no question with those two sides, for the verdict tests.
    private func verdict(yes: Option, no: Option, quiet: Bool = false) -> Invocation {
        Invocation(
            context: .text("c"),
            questions: [Question(instructions: "Q", kind: .verdict(yes: yes, no: no))],
            quiet: quiet
        )
    }
}
