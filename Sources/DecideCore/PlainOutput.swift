import Foundation

/// One question's plain-output line: `[name=]answer`, then the stats field
/// when the question asked for its numbers, then one field per option,
/// level, or side when it asked for the whole distribution.
///
/// A tab separates the fields, and a space the values inside the stats
/// field, so `cut -f2` is the stats and `cut -f3-` the distribution. `=`
/// marks the decision, `name=answer`; `:` marks a number with its label. A
/// probability never holds a colon, so a split at the last colon always
/// gives the number, whatever the id holds. The parser refuses an id that
/// holds a tab, so no field of a line can split in two.
///
/// An answer below the question's `--min-confidence` bar prints as nothing,
/// so the line is `name=` or empty, or as the question's `--fallback` when
/// it has one. The fields after it are the model's numbers as they stand,
/// and `probability:` is the probability of the answer the model would have
/// given, fallback or not. The run names the question on stderr either way,
/// and exits 2 when an unsure question has no fallback.
public enum PlainOutput {
    /// The line for one answer, with no trailing newline: the caller prints
    /// it. `question` and `outcome` are one pair, as `Runner.decide` gives
    /// them.
    public static func line(for question: Question, outcome: Outcome) -> String {
        let answer = Runner.printedAnswer(for: question, outcome: outcome) ?? ""
        var line = prefix(question) + answer
        guard question.detail != .answer else { return line }
        line +=
            "\t" + "confidence:" + number(outcome.confidence)
            + " probability:" + number(outcome.probabilities[outcome.answer] ?? 0)
        if case .rating = question.kind, let score = outcome.score {
            line += " score:" + number(score)
        }
        guard question.detail == .distribution else { return line }
        switch question.kind {
        case .choice(let options):
            for option in options {
                line += field(option.id, probability: probability(option.id, in: outcome))
            }
        case .rating(let levels):
            for (index, level) in levels.enumerated() {
                line += field(
                    level.id + "[" + String(index) + "]",
                    probability: probability(level.id, in: outcome)
                )
            }
        case .verdict(let yes, let no):
            for side in [yes, no] {
                line += field(side.id, probability: probability(side.id, in: outcome))
            }
        }
        return line
    }

    /// The line for a question on a run the model server failed, when every
    /// question has a fallback: `[name=]fallback` and nothing after it,
    /// because there are no numbers, even with `--stats`.
    public static func fallbackLine(for question: Question) -> String {
        prefix(question) + (question.fallback ?? "")
    }

    /// `name=` for a named question, and nothing for an unnamed one.
    private static func prefix(_ question: Question) -> String {
        question.name.map { "\($0)=" } ?? ""
    }

    /// One distribution field: a tab, the label, a colon, and the number.
    /// The label is the id, except on a level, which carries its index in
    /// brackets.
    private static func field(_ label: String, probability: Double) -> String {
        "\t" + label + ":" + number(probability)
    }

    /// The probability of one option, level, or side. An id the outcome does
    /// not hold reads as 0, as in `JSONOutput`.
    private static func probability(_ id: String, in outcome: Outcome) -> Double {
        outcome.probabilities[id] ?? 0
    }

    /// A confidence, a probability, or a score with three decimals, fixed.
    /// The format takes no locale, so the separator is always a dot.
    /// `--json` prints the exact value. Every number the runner hands over
    /// is finite and not negative: the library clamps a confidence to 0...1
    /// and rejects a non-finite score or probability, so `nan` and `-0.000`
    /// never print.
    private static func number(_ value: Double) -> String {
        String(format: "%.3f", value)
    }
}
