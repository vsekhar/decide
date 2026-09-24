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
public enum PlainOutput {
    /// The line for one answer, with no trailing newline: the caller prints
    /// it. `question` and `outcome` are one pair, as `Runner.decide` gives
    /// them.
    public static func line(for question: Question, outcome: Outcome) -> String {
        var line = (question.name.map { "\($0)=" } ?? "") + outcome.answer
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
