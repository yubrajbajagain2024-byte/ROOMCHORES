import Foundation

/// One roommate's line on the scoreboard.
struct ScoreEntry: Identifiable {
    let roommate: Roommate
    /// Points earned since the current cycle started.
    let thisCycle: Double
    let allTime: Double
    let tasksThisCycle: Int

    var id: UUID { roommate.id }
}

/// Earned points — what the scoreboard shows.
///
/// A task counts once it's done: at its final points after ratings, or at its quoted points
/// while ratings are still coming in. Tasks still on someone's list, and skipped tasks,
/// earn nothing. This is deliberately separate from `FairnessEngine`, which also counts work
/// people have *taken on* when deciding who gets the next chore.
enum Scores {

    static func isEarned(_ assignment: Assignment) -> Bool {
        assignment.status == .settled || assignment.status == .awaitingReview
    }

    /// Every task this roommate has finished, newest first.
    static func completedTasks(by roommate: Roommate, in household: Household) -> [Assignment] {
        (household.assignments ?? [])
            .filter { $0.assignee?.id == roommate.id && isEarned($0) }
            .sorted { ($0.completedAt ?? $0.dueDate) > ($1.completedAt ?? $1.dueDate) }
    }

    /// Judged by when the task was *finished*, so a chore handed out last week but done
    /// this week counts towards this week.
    static func isInCurrentCycle(_ assignment: Assignment, household: Household) -> Bool {
        (assignment.completedAt ?? assignment.assignedAt) >= household.currentCycleStart
    }

    static func total(_ assignments: [Assignment]) -> Double {
        assignments.reduce(0) { $0 + $1.effectivePoints }
    }

    /// Everyone, highest this-cycle score first; ties broken by name so the order is stable.
    static func board(for household: Household) -> [ScoreEntry] {
        household.sortedMembers
            .map { member in
                let done = completedTasks(by: member, in: household)
                let thisCycle = done.filter { isInCurrentCycle($0, household: household) }
                return ScoreEntry(
                    roommate: member,
                    thisCycle: total(thisCycle),
                    allTime: total(done),
                    tasksThisCycle: thisCycle.count
                )
            }
            .sorted {
                $0.thisCycle != $1.thisCycle
                    ? $0.thisCycle > $1.thisCycle
                    : $0.roommate.name < $1.roommate.name
            }
    }

    /// Tasks other people have finished that are still waiting on this roommate's rating,
    /// newest first.
    static func awaitingRating(from rater: Roommate, in household: Household) -> [Assignment] {
        (household.assignments ?? [])
            .filter { $0.status == .awaitingReview && $0.assignee?.id != rater.id && !$0.hasRated(rater) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }
}

extension Date {
    /// Feed-style timestamps: "Just now", "12m", "3h", "2d", then a date.
    var shortRelative: String {
        let seconds = Date().timeIntervalSince(self)
        switch seconds {
        case ..<60:          return "Just now"
        case ..<3600:        return "\(Int(seconds / 60))m"
        case ..<86_400:      return "\(Int(seconds / 3600))h"
        case ..<(7 * 86_400): return "\(Int(seconds / 86_400))d"
        default:
            let formatter = DateFormatter()
            formatter.dateFormat = isInSameYear(as: Date()) ? "d MMM" : "d MMM yyyy"
            return formatter.string(from: self)
        }
    }
}
