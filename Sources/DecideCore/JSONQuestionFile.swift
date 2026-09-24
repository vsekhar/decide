import Foundation

/// The JSON question file format: an object with a `questions` array, in the
/// README's schema.
///
/// The decoder is strict. It refuses an unknown key, a missing key, a value
/// of the wrong type, and a question that mixes kinds, so a typo is an error
/// and not a field the tool skips.
///
/// No message holds a value from the file except a key name, an id, or a
/// name, where the message is about that construct. A message names the
/// JSON path of the problem where it has one, as in `questions[1].levels[0].id`.
public enum JSONQuestionFile {
    /// Decodes the text of a JSON question file. Pure: no I/O. `path` only
    /// names the file in a message. Questions come back in file order.
    ///
    /// Each question has `instructions`: a string, or an object with a
    /// `question` and optional `rules`. It may have a `name`, a
    /// `min-confidence`, a `fallback`, and `stats` and `distribution` flags.
    /// `options` make a choice, `levels` make a rating, and neither makes a
    /// yes/no question, which `yes` and `no` sides decorate. Every problem
    /// throws a `ConfigError` at line 0 that names the file, and the JSON
    /// path where the problem has one.
    public static func questions(from text: String, path: String) throws(ConfigError) -> [Question] {
        func fail(_ refusal: Refusal) -> ConfigError {
            let problem = refusal.path.isEmpty ? refusal.problem : "\(refusal.path): \(refusal.problem)"
            return ConfigError(path: path, line: 0, problem: problem)
        }

        let file: FileBody
        do {
            file = try JSONDecoder().decode(FileBody.self, from: Data(text.utf8))
        } catch let refusal as Refusal {
            throw fail(refusal)
        } catch let error as DecodingError {
            throw fail(syntaxRefusal(error))
        } catch {
            throw fail(Refusal(path: "", problem: "not valid JSON"))
        }

        do {
            return try questions(in: file)
        } catch {
            throw fail(error)
        }
    }

    /// Checks the decoded file as a whole and builds its questions. A name
    /// is unique within the file; the run checks it across files.
    private static func questions(in file: FileBody) throws(Refusal) -> [Question] {
        guard !file.questions.isEmpty else {
            throw Refusal(path: "questions", problem: "a question file needs at least one question")
        }
        var names: Set<String> = []
        var questions: [Question] = []
        for (offset, body) in file.questions.enumerated() {
            let question = try body.question(number: offset + 1)
            if let name = question.name {
                guard names.insert(name).inserted else {
                    throw Refusal(
                        path: "\(body.path).name",
                        problem: "question name \"\(name)\" is used twice"
                    )
                }
            }
            questions.append(question)
        }
        return questions
    }

    /// The refusal for an error Foundation throws before any of this file's
    /// types see a value: most often a syntax error. Foundation's own text
    /// often quotes the file, so the message keeps only the byte offset, or
    /// the one description known to hold no file content.
    private static func syntaxRefusal(_ error: DecodingError) -> Refusal {
        guard case .dataCorrupted(let context) = error else {
            return Refusal(path: "", problem: "not valid JSON")
        }
        var problem = "not valid JSON"
        if let underlying = context.underlyingError as NSError? {
            if let offset = underlying.userInfo["NSJSONSerializationErrorIndex"] as? Int {
                problem += " at byte offset \(offset)"
            } else if underlying.userInfo[NSDebugDescriptionErrorKey] as? String
                == endOfFile
            {
                problem += ": \(endOfFile)"
            }
        }
        return Refusal(path: render(context.codingPath), problem: problem)
    }

    /// Foundation's description of a text that ends too soon, empty text
    /// included. It holds no file content.
    private static let endOfFile = "Unexpected end of file"

    /// Renders a coding path as `questions[1].levels[0].id`: a key after a
    /// dot, an index in brackets. The empty path is the empty string.
    fileprivate static func render(_ codingPath: [any CodingKey]) -> String {
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result
    }
}

/// A problem in the file, before it becomes a `ConfigError`. `path` is the
/// rendered JSON path, empty for the whole file.
private struct Refusal: Error {
    let path: String
    let problem: String
}

/// Any key of a JSON object, so an object's keys can be checked against the
/// list it allows.
private struct Key: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// One JSON object whose keys are checked. Reads each value with its own
/// message for a wrong type, so every refusal names the key's path.
private struct Object {
    let container: KeyedDecodingContainer<Key>
    /// The object's JSON path.
    let path: String

    /// Opens the object at the decoder. Refuses a value that is not an object
    /// with `problem`, and a key not in `allowed` by its name.
    init(_ decoder: any Decoder, allowed: Set<String>, problem: String = "expected an object") throws {
        path = JSONQuestionFile.render(decoder.codingPath)
        do {
            container = try decoder.container(keyedBy: Key.self)
        } catch DecodingError.typeMismatch(_, _), DecodingError.valueNotFound(_, _) {
            throw Refusal(path: path, problem: problem)
        }
        if let unknown = container.allKeys.map(\.stringValue).filter({ !allowed.contains($0) }).min() {
            throw Refusal(path: path, problem: "unknown key \"\(unknown)\"")
        }
    }

    /// The value at `key`, or nil when the key is absent. A null is a wrong
    /// type, not an absent key. `noun` is what the key holds, for the message.
    func optional<T: Decodable>(_ key: String, _ type: T.Type, _ noun: String) throws -> T? {
        let codingKey = Key(stringValue: key)
        guard container.contains(codingKey) else { return nil }
        do {
            return try container.decode(type, forKey: codingKey)
        } catch DecodingError.typeMismatch(_, _), DecodingError.valueNotFound(_, _) {
            let keyPath = path.isEmpty ? key : "\(path).\(key)"
            throw Refusal(path: keyPath, problem: "expected \(noun)")
        }
    }

    /// The number at `key`, or nil when the key is absent. Unlike `optional`,
    /// it also refuses a value the `Double` cannot hold, such as `1e999`.
    /// Foundation refuses a malformed number, with its offset, before any
    /// decoding starts, so the only other error a number can throw here is
    /// that one. A string can still hold a bad escape at this point, which
    /// is why `optional` lets other errors go on to the caller.
    func optionalNumber(_ key: String, _ noun: String) throws -> Double? {
        let codingKey = Key(stringValue: key)
        guard container.contains(codingKey) else { return nil }
        let keyPath = path.isEmpty ? key : "\(path).\(key)"
        do {
            return try container.decode(Double.self, forKey: codingKey)
        } catch DecodingError.typeMismatch(_, _), DecodingError.valueNotFound(_, _) {
            throw Refusal(path: keyPath, problem: "expected \(noun)")
        } catch let error where !(error is DecodingError) {
            throw Refusal(path: keyPath, problem: "expected \(noun)")
        }
    }

    /// The value at `key`. Refuses an absent key.
    func required<T: Decodable>(_ key: String, _ type: T.Type, _ noun: String) throws -> T {
        guard let value = try optional(key, type, noun) else {
            throw Refusal(path: path, problem: "missing key \"\(key)\"")
        }
        return value
    }
}

/// The whole file: an object with one key, `questions`.
private struct FileBody: Decodable {
    let questions: [QuestionBody]

    init(from decoder: any Decoder) throws {
        let object = try Object(
            decoder,
            allowed: ["questions"],
            problem: "a question file is an object with a questions array"
        )
        questions = try object.required("questions", [QuestionBody].self, "an array of questions")
    }
}

/// One question as the file writes it.
private struct QuestionBody: Decodable {
    /// The question's JSON path, for messages after decoding.
    let path: String
    let instructions: InstructionsBody
    let name: String?
    let options: [OptionBody]?
    let levels: [OptionBody]?
    let yes: OptionBody?
    let no: OptionBody?
    let minimumConfidence: Double?
    let fallback: String?
    let stats: Bool?
    let distribution: Bool?

    init(from decoder: any Decoder) throws {
        let object = try Object(
            decoder,
            allowed: [
                "instructions", "name", "options", "levels", "yes", "no",
                "min-confidence", "fallback", "stats", "distribution",
            ]
        )
        path = object.path
        instructions = try object.required(
            "instructions", InstructionsBody.self, "a string or an object"
        )
        name = try object.optional("name", String.self, "a string")
        options = try object.optional("options", [OptionBody].self, "an array of options")
        levels = try object.optional("levels", [OptionBody].self, "an array of levels")
        yes = try object.optional("yes", OptionBody.self, "an object")
        no = try object.optional("no", OptionBody.self, "an object")
        let bar = try object.optionalNumber("min-confidence", Self.barNoun)
        if let bar, !(bar.isFinite && (0...1).contains(bar)) {
            throw Refusal(path: "\(path).min-confidence", problem: "expected \(Self.barNoun)")
        }
        minimumConfidence = bar
        fallback = try object.optional("fallback", String.self, "a string")
        stats = try object.optional("stats", Bool.self, "true or false")
        distribution = try object.optional("distribution", Bool.self, "true or false")
    }

    /// What `min-confidence` holds, for its message.
    private static let barNoun = "a number from 0 to 1"

    /// Builds the question. `number` is its 1-based place in the file, as
    /// the command line counts questions.
    func question(number: Int) throws(Refusal) -> Question {
        if let name, !CommandLineParser.isIdentifier(name) {
            throw Refusal(
                path: "\(path).name",
                problem: "not a valid name: a letter or _ then letters, digits, or _"
            )
        }
        let kinds = [options != nil, levels != nil, yes != nil || no != nil]
        guard kinds.filter({ $0 }).count <= 1 else {
            throw Refusal(path: path, problem: "question \(number) mixes options, levels, yes, or no")
        }
        let questionKind = try kind(number: number)
        try checkFallback(questionKind)
        return Question(
            instructions: instructions.question,
            kind: questionKind,
            minimumConfidence: minimumConfidence,
            fallback: fallback,
            name: name,
            rules: instructions.rules,
            detail: distribution == true ? .distribution : stats == true ? .stats : .answer
        )
    }

    /// Refuses a fallback that is empty or holds a tab or a line break, and
    /// on a yes/no question one that is neither side's value.
    private func checkFallback(_ kind: Question.Kind) throws(Refusal) {
        guard let fallback else { return }
        let fallbackPath = "\(path).fallback"
        guard !fallback.isEmpty else { throw Refusal(path: fallbackPath, problem: "is empty") }
        let breaking: Set<Unicode.Scalar> = ["\t", "\n", "\r"]
        guard !fallback.unicodeScalars.contains(where: breaking.contains) else {
            throw Refusal(path: fallbackPath, problem: "holds a tab or a newline")
        }
        if case .verdict(let yes, let no) = kind, fallback != yes.id, fallback != no.id {
            throw Refusal(path: fallbackPath, problem: "is not the yes or no value")
        }
    }

    /// The question's kind, from the one kind key it has.
    private func kind(number: Int) throws(Refusal) -> Question.Kind {
        if let options {
            guard !options.isEmpty else {
                throw Refusal(path: "\(path).options", problem: "a choice needs at least one option")
            }
            return .choice(try values(options, noun: "option", number: number))
        }
        if let levels {
            guard levels.count >= 2 else {
                throw Refusal(path: "\(path).levels", problem: "a rating needs at least two levels")
            }
            return .rating(try values(levels, noun: "level", number: number))
        }
        let yesSide = try yes?.option() ?? Option(id: "yes")
        let noSide = try no?.option() ?? Option(id: "no")
        guard yesSide.id != noSide.id else {
            throw Refusal(path: path, problem: "question \(number) uses the same value for yes and no")
        }
        return .verdict(yes: yesSide, no: noSide)
    }

    /// The options or levels, in file order. Refuses an id the list repeats.
    private func values(_ bodies: [OptionBody], noun: String, number: Int) throws(Refusal) -> [Option] {
        var ids: Set<String> = []
        var values: [Option] = []
        for body in bodies {
            let value = try body.option()
            guard ids.insert(value.id).inserted else {
                throw Refusal(
                    path: "\(body.path).id",
                    problem: "question \(number) repeats the \(noun) \"\(value.id)\""
                )
            }
            values.append(value)
        }
        return values
    }
}

/// A question's instructions: a string, or an object with a `question` and
/// optional `rules`.
private struct InstructionsBody: Decodable {
    let question: String
    let rules: [String]

    init(from decoder: any Decoder) throws {
        // Only a wrong type or a null moves on to the object. Any other
        // error, such as a bad escape in the string, goes on to the caller.
        do {
            question = try decoder.singleValueContainer().decode(String.self)
            rules = []
            return
        } catch DecodingError.typeMismatch(_, _), DecodingError.valueNotFound(_, _) {}
        let object = try Object(
            decoder,
            allowed: ["question", "rules"],
            problem: "expected a string or an object"
        )
        question = try object.required("question", String.self, "a string")
        rules = try object.optional("rules", [String].self, "an array of strings") ?? []
    }
}

/// An option, a level, or a yes/no side as the file writes it.
private struct OptionBody: Decodable {
    /// The object's JSON path, for messages after decoding.
    let path: String
    let id: String
    let summary: String?
    let notFor: String?
    let examples: [String]
    let signals: [String]

    init(from decoder: any Decoder) throws {
        let object = try Object(
            decoder,
            allowed: ["id", "summary", "not_for", "examples", "signals"]
        )
        path = object.path
        id = try object.required("id", String.self, "a string")
        summary = try object.optional("summary", String.self, "a string")
        notFor = try object.optional("not_for", String.self, "a string")
        examples = try object.optional("examples", [String].self, "an array of strings") ?? []
        signals = try object.optional("signals", [String].self, "an array of strings") ?? []
    }

    /// The option. Refuses an empty id, and an id holding `=`, a tab, or a
    /// line break, which would break a plain output line.
    func option() throws(Refusal) -> Option {
        guard !id.isEmpty else { throw Refusal(path: "\(path).id", problem: "is empty") }
        let breaking: Set<Unicode.Scalar> = ["=", "\t", "\n", "\r"]
        guard !id.unicodeScalars.contains(where: breaking.contains) else {
            throw Refusal(path: "\(path).id", problem: "holds =, a tab, or a newline")
        }
        return Option(
            id: id,
            description: summary,
            notFor: notFor,
            examples: examples,
            signals: signals
        )
    }
}
