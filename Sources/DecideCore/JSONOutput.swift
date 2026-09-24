/// The `--json` line: one object keyed by question id, in question order,
/// each value the answer by kind.
///
/// Each value carries `kind`, `answer`, `confidence`, and `probabilities`,
/// which mean the same thing on every kind: `answer` is the string plain
/// output prints, and `probabilities[answer]` is its probability. A rating
/// adds `score`, the model's expected level index; a verdict adds `verdict`,
/// true when the answer is the yes side. Keys come in that order, and
/// probabilities in the question's declared order, so the output is stable
/// and diffable. The text is written here rather than by `JSONEncoder`,
/// which does not keep key order.
///
/// An answer below the question's `--min-confidence` bar has `"answer": null`
/// and then `"unsure": true`, and a verdict's `verdict` is null too; the
/// numbers are the model's as they stand. A sure answer has no `unsure` key,
/// so its object is unchanged.
public enum JSONOutput {
    /// The line for the answers, ending in one newline. `questions` and
    /// `outcomes` pair up by position, one outcome per question, as
    /// `Runner.decide` gives them.
    public static func line(for questions: [Question], outcomes: [Outcome]) -> String {
        precondition(
            questions.count == outcomes.count,
            "JSONOutput needs one outcome per question, got \(outcomes.count) for \(questions.count)."
        )
        let pairs = zip(questions, outcomes).map { question, outcome in
            (key: outcome.questionID, value: value(question, outcome))
        }
        return object(pairs) + "\n"
    }

    /// One answer as a JSON object. The kind decides which keys it has and
    /// the order they come in.
    private static func value(_ question: Question, _ outcome: Outcome) -> String {
        switch question.kind {
        case .choice(let options):
            return object(
                [("kind", string("choice"))] + answer(outcome) + [
                    ("confidence", number(outcome.confidence)),
                    ("probabilities", probabilities(ids: options.map(\.id), from: outcome)),
                ]
            )
        case .rating(let levels):
            return object(
                [("kind", string("rating"))] + answer(outcome) + [
                    ("score", outcome.score.map(number) ?? "null"),
                    ("confidence", number(outcome.confidence)),
                    ("probabilities", probabilities(ids: levels.map(\.id), from: outcome)),
                ]
            )
        case .verdict(let yes, let no):
            let verdict = outcome.unsure ? "null" : outcome.answer == yes.id ? "true" : "false"
            return object(
                [("kind", string("verdict"))] + answer(outcome) + [
                    ("verdict", verdict),
                    ("confidence", number(outcome.confidence)),
                    ("probabilities", probabilities(ids: [yes.id, no.id], from: outcome)),
                ]
            )
        }
    }

    /// The `answer` pair, and for an unsure answer a null answer and then
    /// `"unsure": true`.
    private static func answer(_ outcome: Outcome) -> [(key: String, value: String)] {
        guard outcome.unsure else { return [("answer", string(outcome.answer))] }
        return [("answer", "null"), ("unsure", "true")]
    }

    /// The probabilities object, keyed by the ids in declared order. An id
    /// the outcome does not hold reads as 0.
    private static func probabilities(ids: [String], from outcome: Outcome) -> String {
        object(ids.map { ($0, number(outcome.probabilities[$0] ?? 0)) })
    }

    /// A JSON object from keys and already-rendered values, in the order
    /// given.
    private static func object(_ pairs: [(key: String, value: String)]) -> String {
        "{" + pairs.map { string($0.key) + ":" + $0.value }.joined(separator: ",") + "}"
    }

    /// A JSON number: the shortest text that reads back as the same Double.
    /// A very small or large value takes the exponent form, which JSON
    /// allows. Every number the runner hands over is finite: the library
    /// rejects a non-finite score, probability, or confidence before an
    /// answer reaches the tool.
    private static func number(_ value: Double) -> String {
        value.description
    }

    /// A JSON string: the text in quotes, with the characters JSON needs
    /// escaped. Non-ASCII and `/` go through as they are.
    private static func string(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{0A}": out += "\\n"
            case "\u{0D}": out += "\\r"
            case "\u{09}": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    let digits = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - digits.count) + digits
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
