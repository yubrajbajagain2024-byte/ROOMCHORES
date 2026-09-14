import Foundation

/// Turns "how hard is this job" into a number.
///
/// Three inputs, because roommates argue about three different things: a chore can be
/// quick but disgusting (scrubbing the toilet), long but easy (a laundry cycle), or
/// physically heavy (hauling recycling down three flights). Scoring only on time would
/// under-pay the first, only on effort would under-pay the second.
enum PointsEngine {

    // Weights. Tuned so a 5-minute bin run lands around 4 points and a 45-minute
    // deep-clean lands around 22 — a spread wide enough to feel fair, narrow enough
    // that no single chore dominates a week.
    static let difficultyWeight = 1.4
    static let laborWeight = 1.4
    /// Per minute. 10 minutes of work is worth ~2.8 points on its own.
    static let minuteWeight = 0.28
    /// Pulls the floor down so trivial jobs do not all bunch up at the same value.
    static let baseOffset = 1.5

    static func rawScore(for values: ChoreValues) -> Double {
        (values.difficulty * difficultyWeight)
            + (values.labor * laborWeight)
            + (values.minutes * minuteWeight)
            - baseOffset
    }

    static func points(for values: ChoreValues) -> Int {
        max(1, Int(rawScore(for: values).rounded()))
    }

    /// Split of a chore's score by input, for the "why is this worth 13 points?" breakdown.
    static func breakdown(for values: ChoreValues) -> [(label: String, points: Double)] {
        [
            ("Difficulty", values.difficulty * difficultyWeight),
            ("Physical effort", values.labor * laborWeight),
            ("Time", values.minutes * minuteWeight)
        ]
    }

    // MARK: - Quality multiplier

    /// How peer quality ratings scale the payout.
    ///
    /// A 3 ("done properly") pays exactly what the chore is worth. Sloppy work pays less,
    /// but never zero — the job still got done. Excellent work pays a modest premium, kept
    /// small on purpose so the incentive is to do chores, not to farm compliments.
    static func qualityMultiplier(averageScore: Double) -> Double {
        let score = min(5, max(1, averageScore))
        if score <= 3 {
            return 0.6 + (score - 1) * 0.2   // 1 → 0.60, 3 → 1.00
        } else {
            return 1.0 + (score - 3) * 0.1   // 3 → 1.00, 5 → 1.20
        }
    }

    /// Final points for a completed assignment. With no ratings in, the chore pays
    /// face value — silence is not treated as criticism.
    static func settledPoints(quoted: Int, averageQuality: Double?) -> Double {
        guard let averageQuality else { return Double(quoted) }
        return (Double(quoted) * qualityMultiplier(averageScore: averageQuality) * 10).rounded() / 10
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
}
