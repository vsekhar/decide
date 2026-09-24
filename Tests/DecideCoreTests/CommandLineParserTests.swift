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
                        context: .single(.file("ticket.txt")),
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
                        context: .single(.file("ticket.txt")),
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
                        context: .single(.file("ticket.txt")),
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
                        context: .single(.file("ticket.txt")),
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
                        context: .single(.file("ticket.txt")),
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
        #expect(result == .run(Invocation(context: .single(.file("ticket.txt")), questions: [question])))
    }

    @Test("--context takes text with spaces verbatim")
    func contextText() throws {
        let result = try CommandLineParser.parse(["--context", "text with spaces", "Q", "--option", "a"])
        #expect(result == .run(Invocation(context: .single(.text("text with spaces")), questions: [question])))
    }

    @Test("--context= with nothing after the = is empty text")
    func contextEqualsEmpty() throws {
        let result = try CommandLineParser.parse(["--context=", "Q", "--option", "a"])
        #expect(result == .run(Invocation(context: .single(.text("")), questions: [question])))
    }

    @Test("An @ after the first character stays literal text")
    func contextLateAtSign() throws {
        let result = try CommandLineParser.parse(["--context", "mail me@example.com", "Q", "--option", "a"])
        #expect(result == .run(Invocation(context: .single(.text("mail me@example.com")), questions: [question])))
    }

    @Test("--context name=@path is a named context from a file")
    func namedFileContext() throws {
        let result = try CommandLineParser.parse([
            "--context", "ticket=@ticket.txt", "Q", "--option", "a",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .named([NamedContext(name: "ticket", source: .file("ticket.txt"))]),
                        questions: [question]
                    )
                )
        )
    }

    @Test("The README two-file example parses to two named contexts in order")
    func twoNamedContexts() throws {
        let result = try CommandLineParser.parse([
            "--context", "ticket=@ticket.txt",
            "--context", "refund_policy=@refund_policy.txt",
            "Should we issue a refund?",
            "--yes", "yes=Allowed by refund_policy and requested in ticket",
            "--no", "no",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .named([
                            NamedContext(name: "ticket", source: .file("ticket.txt")),
                            NamedContext(name: "refund_policy", source: .file("refund_policy.txt")),
                        ]),
                        questions: [
                            Question(
                                instructions: "Should we issue a refund?",
                                kind: .verdict(
                                    yes: Option(
                                        id: "yes",
                                        description: "Allowed by refund_policy and requested in ticket"
                                    ),
                                    no: Option(id: "no")
                                )
                            )
                        ]
                    )
                )
        )
    }

    @Test("--context name=text is a named context of that text")
    func namedTextContext() throws {
        let result = try CommandLineParser.parse([
            "--context", "policy=some text", "Q", "--option", "a",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .named([NamedContext(name: "policy", source: .text("some text"))]),
                        questions: [question]
                    )
                )
        )
    }

    @Test("Three named contexts keep their command-line order")
    func threeNamedContexts() throws {
        let result = try CommandLineParser.parse([
            "--context", "a=1", "--context", "b=2", "--context", "c=3", "Q", "--option", "a",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .named([
                            NamedContext(name: "a", source: .text("1")),
                            NamedContext(name: "b", source: .text("2")),
                            NamedContext(name: "c", source: .text("3")),
                        ]),
                        questions: [question]
                    )
                )
        )
    }

    @Test("--context=name=@path is a named context from a file")
    func contextEqualsNamedFile() throws {
        let result = try CommandLineParser.parse(["--context=ticket=@t.txt", "Q", "--option", "a"])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .named([NamedContext(name: "ticket", source: .file("t.txt"))]),
                        questions: [question]
                    )
                )
        )
    }

    @Test("A value with a space or nothing before its = is one unnamed text")
    func contextTextWithAnEqualsSign() throws {
        #expect(
            try CommandLineParser.parse(["--context", "x = 1", "Q", "--option", "a"])
                == .run(Invocation(context: .single(.text("x = 1")), questions: [question]))
        )
        #expect(
            try CommandLineParser.parse(["--context", "=foo", "Q", "--option", "a"])
                == .run(Invocation(context: .single(.text("=foo")), questions: [question]))
        )
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
                        context: .single(.text("c")),
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

    @Test("A line with no --context runs the questions with no context")
    func noContext() throws {
        #expect(
            try CommandLineParser.parse(["Is Atlanta the capital of Georgia?"])
                == .run(
                    Invocation(
                        context: nil,
                        questions: [
                            Question(
                                instructions: "Is Atlanta the capital of Georgia?",
                                kind: .verdict(yes: Option(id: "yes"), no: Option(id: "no"))
                            )
                        ],
                        quiet: false
                    )
                )
        )
    }

    @Test("A bare question takes --quiet")
    func noContextQuiet() throws {
        #expect(
            try CommandLineParser.parse(["Q?", "-q"])
                == .run(
                    Invocation(
                        context: nil,
                        questions: [
                            Question(
                                instructions: "Q?",
                                kind: .verdict(yes: Option(id: "yes"), no: Option(id: "no"))
                            )
                        ],
                        quiet: true
                    )
                )
        )
    }

    @Test("--context @ names no file")
    func contextBareAtSign() {
        #expect(throws: UsageError("--context @ names no file")) {
            try CommandLineParser.parse(["--context", "@", "Q", "--option", "a"])
        }
    }

    @Test("A --context name that is not an identifier is an error")
    func invalidContextName() {
        #expect(
            throws: UsageError(
                "--context name \"1st\" is not valid: a letter or _ then letters, digits, or _"
            )
        ) {
            try CommandLineParser.parse(["--context", "1st=@f.txt", "Q", "--option", "a"])
        }
        #expect(
            throws: UsageError(
                "--context name \"a.b\" is not valid: a letter or _ then letters, digits, or _"
            )
        ) {
            try CommandLineParser.parse(["--context", "a.b=@f.txt", "Q", "--option", "a"])
        }
        // Text before the first = with no whitespace is a name attempt even
        // when it looks like a path or a URL, so such text needs a file.
        #expect(
            throws: UsageError(
                "--context name \"@t.txt\" is not valid: a letter or _ then letters, digits, or _"
            )
        ) {
            try CommandLineParser.parse(["--context", "@t.txt=x", "Q", "--option", "a"])
        }
        #expect(
            throws: UsageError(
                "--context name \"http://x\" is not valid: a letter or _ then letters, digits, or _"
            )
        ) {
            try CommandLineParser.parse(["--context", "http://x=y", "Q", "--option", "a"])
        }
    }

    @Test("A named --context with nothing after its = is an error")
    func namedContextWithoutValue() {
        #expect(throws: UsageError("--context ticket= has no value")) {
            try CommandLineParser.parse(["--context", "ticket=", "Q", "--option", "a"])
        }
    }

    @Test("--context <name>=@ names no file")
    func namedContextBareAtSign() {
        #expect(throws: UsageError("--context ticket=@ names no file")) {
            try CommandLineParser.parse(["--context", "ticket=@", "Q", "--option", "a"])
        }
    }

    @Test("A named and an unnamed --context together are an error, in either order")
    func mixedContexts() {
        let mixed = UsageError(
            """
            every --context needs a name when there is more than one, \
            like --context ticket=@ticket.txt
            """
        )
        #expect(throws: mixed) {
            try CommandLineParser.parse(["--context", "a=@x", "--context", "@y", "Q", "--option", "a"])
        }
        #expect(throws: mixed) {
            try CommandLineParser.parse(["--context", "@y", "--context", "a=@x", "Q", "--option", "a"])
        }
    }

    @Test("A --context name used twice is an error")
    func repeatedContextName() {
        #expect(throws: UsageError("--context names \"a\" twice")) {
            try CommandLineParser.parse(["--context", "a=@x", "--context", "a=@x", "Q", "--option", "a"])
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
                        context: .single(.text("c")),
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
                            context: .single(.text("c")),
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
                        context: .single(.text("c")),
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

    @Test("--name sets the question's name in either value form")
    func nameForms() throws {
        for line in [
            ["Q", "--name", "team", "--option", "a"],
            ["Q", "--option", "a", "--name=team"],
        ] {
            let result = try CommandLineParser.parse(line)
            #expect(
                result
                    == .run(
                        Invocation(
                            context: nil,
                            questions: [
                                Question(
                                    instructions: "Q",
                                    kind: .choice([Option(id: "a")]),
                                    name: "team"
                                )
                            ]
                        )
                    ),
                "\(line)"
            )
        }
    }

    @Test("--name before any question is an error")
    func nameBeforeQuestion() {
        #expect(throws: UsageError("--name before any question")) {
            try CommandLineParser.parse(["--name", "team", "Q"])
        }
    }

    @Test("A second --name on one question is an error")
    func repeatedName() {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["Q", "--name", "a", "--name", "b"])
        }
        #expect(error?.message == "question 1 (\"Q\") repeats --name")
    }

    @Test("A --name that is not an identifier is an error")
    func invalidName() {
        for value in ["1st", "a-b", "a b", ""] {
            let error = #expect(throws: UsageError.self) {
                try CommandLineParser.parse(["Q", "--name", value])
            }
            #expect(
                error?.message
                    == "question 1 (\"Q\") has an invalid name \"\(value)\": "
                        + "a letter or _ then letters, digits, or _",
                "\(value)"
            )
        }
        // The --flag=value form with nothing after the = is the same empty name.
        let equalsForm = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["Q", "--name="])
        }
        #expect(
            equalsForm?.message
                == "question 1 (\"Q\") has an invalid name \"\": a letter or _ then letters, digits, or _"
        )
    }

    @Test("--name as the last token needs a value")
    func nameNeedsAValue() {
        #expect(throws: UsageError("--name needs a value")) {
            try CommandLineParser.parse(["Q", "--name"])
        }
    }

    @Test("Two questions with one name are an error, and different names parse")
    func namesAreUniqueInTheRun() throws {
        let error = #expect(throws: UsageError.self) {
            try CommandLineParser.parse(["Q1", "--name", "team", "Q2", "--name", "team"])
        }
        #expect(error?.message == "question name \"team\" is used twice")

        let result = try CommandLineParser.parse([
            "Q1", "--name", "team", "Q2", "--name", "refund",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: nil,
                        questions: [
                            Question(
                                instructions: "Q1",
                                kind: .verdict(yes: Option(id: "yes"), no: Option(id: "no")),
                                name: "team"
                            ),
                            Question(
                                instructions: "Q2",
                                kind: .verdict(yes: Option(id: "yes"), no: Option(id: "no")),
                                name: "refund"
                            ),
                        ]
                    )
                )
        )
    }

    @Test("--name goes on a choice, a rating, and a yes/no question")
    func nameOnEveryKind() throws {
        let result = try CommandLineParser.parse([
            "Q1", "--name", "a", "--option", "x",
            "Q2", "--level", "l", "--level", "m", "--name", "b",
            "Q3", "--yes", "y", "--name", "c",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: nil,
                        questions: [
                            Question(
                                instructions: "Q1",
                                kind: .choice([Option(id: "x")]),
                                name: "a"
                            ),
                            Question(
                                instructions: "Q2",
                                kind: .rating([Option(id: "l"), Option(id: "m")]),
                                name: "b"
                            ),
                            Question(
                                instructions: "Q3",
                                kind: .verdict(yes: Option(id: "y"), no: Option(id: "no")),
                                name: "c"
                            ),
                        ]
                    )
                )
        )
    }

    @Test("-q with one named yes/no question is allowed")
    func quietWithANamedQuestion() throws {
        let result = try CommandLineParser.parse(["Q?", "--name", "spam", "-q"])
        #expect(
            result
                == .run(
                    Invocation(
                        context: nil,
                        questions: [
                            Question(
                                instructions: "Q?",
                                kind: .verdict(yes: Option(id: "yes"), no: Option(id: "no")),
                                name: "spam"
                            )
                        ],
                        quiet: true
                    )
                )
        )
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

    @Test("--show-names is an unknown flag")
    func showNamesIsUnknown() {
        #expect(throws: UsageError("unknown flag: --show-names")) {
            try CommandLineParser.parse(["Q", "--show-names"])
        }
    }

    @Test("--json anywhere on the line sets json")
    func jsonAnywhere() throws {
        let expected = ParseResult.run(
            Invocation(
                context: .single(.text("c")),
                questions: [
                    Question(instructions: "Q1", kind: .choice([Option(id: "a")])),
                    Question(instructions: "Q2", kind: .choice([Option(id: "b")])),
                ],
                quiet: false,
                json: true
            )
        )
        let lines = [
            ["--json", "--context", "c", "Q1", "--option", "a", "Q2", "--option", "b"],
            ["--context", "c", "Q1", "--option", "a", "--json", "Q2", "--option", "b"],
            ["--context", "c", "Q1", "--option", "a", "Q2", "--option", "b", "--json"],
        ]
        for line in lines {
            #expect(try CommandLineParser.parse(line) == expected, "\(line)")
        }
    }

    @Test("A second --json is an error")
    func twoJSON() {
        #expect(throws: UsageError("--json was given twice")) {
            try CommandLineParser.parse(["Q", "--json", "--json"])
        }
    }

    @Test("--json with --quiet is an error in either order")
    func jsonWithQuiet() {
        let lines = [
            ["Q?", "--json", "-q"],
            ["Q?", "-q", "--json"],
            ["Q?", "--quiet", "--json"],
        ]
        for line in lines {
            #expect(throws: UsageError("--json does not go with --quiet"), "\(line)") {
                try CommandLineParser.parse(line)
            }
        }
    }

    @Test("--json alone still needs a question")
    func jsonNeedsAQuestion() {
        #expect(throws: UsageError("no question given")) {
            try CommandLineParser.parse(["--json"])
        }
    }

    @Test("--model sets the run's model in either value form")
    func modelFlag() throws {
        let expected = ParseResult.run(
            Invocation(
                context: nil, questions: [question], quiet: false, model: "a:b", apiKey: nil
            )
        )
        #expect(try CommandLineParser.parse(["--model", "a:b", "Q", "--option", "a"]) == expected)
        #expect(try CommandLineParser.parse(["Q", "--option", "a", "--model=a:b"]) == expected)
    }

    @Test("--api-key sets the run's key in either value form")
    func apiKeyFlag() throws {
        let expected = ParseResult.run(
            Invocation(
                context: nil, questions: [question], quiet: false, model: nil, apiKey: "k"
            )
        )
        #expect(try CommandLineParser.parse(["--api-key", "k", "Q", "--option", "a"]) == expected)
        #expect(try CommandLineParser.parse(["Q", "--option", "a", "--api-key=k"]) == expected)
    }

    @Test("--model and --api-key work anywhere on a line with a context and questions")
    func modelAndKeyAnywhere() throws {
        let result = try CommandLineParser.parse([
            "--model", "a:b",
            "--context", "c",
            "Q1", "--option", "a",
            "Q2", "--option", "b",
            "--api-key", "k",
        ])
        #expect(
            result
                == .run(
                    Invocation(
                        context: .single(.text("c")),
                        questions: [
                            Question(instructions: "Q1", kind: .choice([Option(id: "a")])),
                            Question(instructions: "Q2", kind: .choice([Option(id: "b")])),
                        ],
                        quiet: false,
                        model: "a:b",
                        apiKey: "k"
                    )
                )
        )
    }

    @Test("A second --model or --api-key is an error")
    func modelAndKeyComeOnce() {
        let lines: [(String, [String])] = [
            ("--model", ["Q", "--model", "a:b", "--model=c:d"]),
            ("--api-key", ["Q", "--api-key", "k", "--api-key=k2"]),
        ]
        for (flag, line) in lines {
            #expect(throws: UsageError("\(flag) was given twice"), "\(line)") {
                try CommandLineParser.parse(line)
            }
        }
    }

    @Test("A --model or --api-key value that is empty or blank is an error")
    func modelAndKeyEmptyValue() {
        #expect(throws: UsageError("--model is empty")) {
            try CommandLineParser.parse(["Q", "--model="])
        }
        #expect(throws: UsageError("--model is empty")) {
            try CommandLineParser.parse(["Q", "--model", " "])
        }
        #expect(throws: UsageError("--api-key is empty")) {
            try CommandLineParser.parse(["Q", "--api-key", ""])
        }
    }

    @Test("--model as the last token names the value it needs")
    func modelNeedsAValue() {
        #expect(throws: UsageError("--model needs a value")) {
            try CommandLineParser.parse(["Q", "--model"])
        }
    }

    @Test("--set-config takes --model and --api-key in either value form")
    func setConfigValueForms() throws {
        let expected = ParseResult.setConfig(SetConfig(model: "typesafe:jev-latest", apiKey: "k"))
        #expect(
            try CommandLineParser.parse([
                "--set-config", "--model", "typesafe:jev-latest", "--api-key", "k",
            ]) == expected
        )
        #expect(
            try CommandLineParser.parse([
                "--set-config", "--model=typesafe:jev-latest", "--api-key=k",
            ]) == expected
        )
    }

    @Test("--set-config takes either flag on its own, and --project with it")
    func setConfigOneFlag() throws {
        #expect(
            try CommandLineParser.parse(["--set-config", "--api-key", "k"])
                == .setConfig(SetConfig(model: nil, apiKey: "k"))
        )
        #expect(
            try CommandLineParser.parse([
                "--set-config", "--model", "typesafe:jev-latest", "--project",
            ]) == .setConfig(SetConfig(model: "typesafe:jev-latest", apiKey: nil, project: true))
        )
    }

    @Test("--set-config with only --model writes only the model")
    func setConfigModelAlone() throws {
        #expect(
            try CommandLineParser.parse(["--set-config", "--model", "a:b"])
                == .setConfig(SetConfig(model: "a:b", apiKey: nil))
        )
    }

    @Test("A --set-config value keeps everything after the first =")
    func setConfigValueWithEquals() throws {
        #expect(
            try CommandLineParser.parse(["--set-config", "--api-key=a=b=c"])
                == .setConfig(SetConfig(model: nil, apiKey: "a=b=c"))
        )
    }

    @Test("Any other token with --set-config is an error")
    func setConfigRunsAlone() {
        let lines = [
            ["--set-config", "--model", "typesafe:jev-latest", "Q"],
            ["--set-config", "--context", "c", "--model", "typesafe:jev-latest"],
            ["--set-config", "--model", "typesafe:jev-latest", "-q"],
            ["--set-config", "--model", "typesafe:jev-latest", "--option", "a"],
        ]
        for line in lines {
            #expect(throws: UsageError("--set-config runs alone"), "\(line)") {
                try CommandLineParser.parse(line)
            }
        }
    }

    @Test("--project without --set-config is an error")
    func projectNeedsSetConfig() {
        #expect(throws: UsageError("--project needs --set-config")) {
            try CommandLineParser.parse(["Q", "--project"])
        }
    }

    @Test("--set-config with nothing to write is an error")
    func setConfigNeedsASetting() {
        let lines = [["--set-config"], ["--set-config", "--project"]]
        for line in lines {
            #expect(throws: UsageError("--set-config needs --model or --api-key"), "\(line)") {
                try CommandLineParser.parse(line)
            }
        }
    }

    @Test("Each --set-config flag comes once")
    func setConfigRepeatedFlags() {
        let lines: [(String, [String])] = [
            ("--set-config", ["--set-config", "--set-config", "--model", "typesafe:jev-latest"]),
            ("--model", ["--set-config", "--model", "typesafe:jev-latest", "--model=x:y"]),
            ("--api-key", ["--set-config", "--api-key", "k", "--api-key=k2"]),
            ("--project", ["--set-config", "--api-key", "k", "--project", "--project"]),
        ]
        for (flag, line) in lines {
            #expect(throws: UsageError("\(flag) was given twice"), "\(line)") {
                try CommandLineParser.parse(line)
            }
        }
    }

    @Test("A --set-config value that is empty or blank is an error")
    func setConfigEmptyValue() {
        #expect(throws: UsageError("--model is empty")) {
            try CommandLineParser.parse(["--set-config", "--model="])
        }
        #expect(throws: UsageError("--model is empty")) {
            try CommandLineParser.parse(["--set-config", "--model", " "])
        }
        #expect(throws: UsageError("--api-key is empty")) {
            try CommandLineParser.parse(["--set-config", "--api-key", ""])
        }
    }

    @Test("--api-key with --project is refused")
    func setConfigKeyNeedsTheHomeConfig() {
        #expect(
            throws: UsageError("--api-key is allowed only in the home config, not in a project's")
        ) {
            try CommandLineParser.parse(["--set-config", "--api-key", "k", "--project"])
        }
    }

    @Test("--help and --version win over --set-config")
    func setConfigYieldsToHelpAndVersion() throws {
        #expect(try CommandLineParser.parse(["--set-config", "--help"]) == .help)
        #expect(
            try CommandLineParser.parse(["--set-config", "--version"]) == .version(alone: false)
        )
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
            context: .single(.text("c")),
            questions: [Question(instructions: "Q", kind: .choice([option]))]
        )
    }

    /// One yes/no question with those two sides, for the verdict tests.
    private func verdict(yes: Option, no: Option, quiet: Bool = false) -> Invocation {
        Invocation(
            context: .single(.text("c")),
            questions: [Question(instructions: "Q", kind: .verdict(yes: yes, no: no))],
            quiet: quiet
        )
    }
}
