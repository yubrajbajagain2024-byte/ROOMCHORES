import Foundation

/// Turns "how hard is this job" into a number from 1 to 4.
///
/// Three inputs, because roommates argue about three different things: a chore can be
/// quick but disgusting (scrubbing the toilet), long but easy (a laundry cycle), or
/// physically heavy (hauling recycling down three flights). Scoring only on time would
/// under-pay the first, only on effort would under-pay the second.
///
/// Each input is placed on the same 1–4 level as the points themselves, and the chore is
/// worth the average of the three, rounded to a whole point. That keeps the rule simple
/// enough to explain in one sentence at the kitchen table.
enum PointsEngine {

    static let minimumPoints = 1
    static let maximumPoints = 4
    static var pointRange: ClosedRange<Int> { minimumPoints...maximumPoints }

    // MARK: - Levels

    /// Difficulty and effort are rated 1–5 — five steps gives raters room for "a bit worse
    /// than average" — then stretched onto the 1–4 points scale.
    static func level(forRating rating: Double) -> Double {
        let clamped = min(5, max(1, rating))
        return 1 + (clamped - 1) * 0.75
    }

    /// Time is banded rather than scaled, so "about 15 minutes" and "about 18 minutes"
    /// don't produce different answers.
    static func level(forMinutes minutes: Double) -> Double {
        switch minutes {
        case ...10: return 1
        case ...20: return 2
        case ...40: return 3
        default:    return 4
        }
    }

    /// The three levels a chore is judged on, each from 1 to 4.
    static func breakdown(for values: ChoreValues) -> [(label: String, level: Double)] {
        [
            ("Difficulty", level(forRating: values.difficulty)),
            ("Physical effort", level(forRating: values.labor)),
            ("Time", level(forMinutes: values.minutes))
        ]
    }

    /// The unrounded average of the three levels, 1.0–4.0.
    static func exactScore(for values: ChoreValues) -> Double {
        let levels = breakdown(for: values).map(\.level)
        return levels.reduce(0, +) / Double(levels.count)
    }

    static func points(for values: ChoreValues) -> Int {
        let rounded = Int(exactScore(for: values).rounded())
        return min(maximumPoints, max(minimumPoints, rounded))
    }

    // MARK: - Quality

    /// How peer quality ratings scale the payout.
    ///
    /// Three stars or more ("done properly") pays the chore's full points. Below that the
    /// payout drops, down to half for work that has to be redone — but never to zero, since
    /// the job still got done. There is no bonus above full points: a 4-point chore pays at
    /// most 4, so every payout stays on the same 1–4 scale as the chore itself.
    static func qualityMultiplier(averageScore: Double) -> Double {
        let score = min(5, max(1, averageScore))
        guard score < 3 else { return 1.0 }
        return 0.5 + (score - 1) * 0.25   // 1 → 0.50, 2 → 0.75, 3 → 1.00
    }

    /// Final points for a completed assignment, in half-point steps. With no ratings in,
    /// the chore pays its full points — silence is not treated as criticism.
    static func settledPoints(quoted: Int, averageQuality: Double?) -> Double {
        guard let averageQuality else { return Double(quoted) }
        let raw = Double(quoted) * qualityMultiplier(averageScore: averageQuality)
        return max(0.5, (raw * 2).rounded() / 2)
    }

    static func describeQuality(_ score: Double) -> String {
        switch score {
        case ..<1.5:  return "Needs redoing"
        case ..<2.5:  return "Half done"
        case ..<3.5:  return "Done properly"
        case ..<4.5:  return "Done well"
        default:      return "Spotless"
        }
    }

    // MARK: - Display

    /// "3" for whole points, "2.5" for half points.
    static func format(_ points: Double) -> String {
        let halves = (points * 2).rounded() / 2
        return halves == halves.rounded() ? String(Int(halves)) : String(format: "%.1f", halves)
    }
}
