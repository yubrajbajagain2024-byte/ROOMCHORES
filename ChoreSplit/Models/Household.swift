import Foundation
import SwiftData

@Model
final class Household {
    var id: UUID = UUID()
    var name: String = "Our place"

    /// Length of a balancing cycle in days. Fairness is judged inside one cycle,
    /// not over all time, so a bad week can actually be recovered from.
    var cycleLengthDays: Int = 7
    var cycleStartDate: Date = Date()

    /// Where the household is in the shared setup flow.
    var setupStageRaw: String = SetupStage.household.rawValue

    /// How far below your fair share you can drift before the app steps in and
    /// hands you extra work. 0.10 means "more than 10% under your target".
    var fairnessTolerance: Double = 0.10

    /// Peer ratings stay hidden until at least this many are in. With a threshold
    /// of 2, a single rater can never be identified by elimination in a 3-person flat.
    var minimumRatingsToReveal: Int = 2

    /// How long roommates have to rate a completed chore before its points settle
    /// at the un-rated default.
    var ratingWindowHours: Int = 48

    /// Whether the app may hand out catch-up chores on its own.
    var autoAssignEnabled: Bool = true

    // MARK: - Shared groups

    /// True for a group that lives on the server and syncs between phones. The id matches the
    /// server's group id. False for the on-device demo household.
    var isShared: Bool = false
    var inviteCode: String = ""
    var lastSyncedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Roommate.household)
    var members: [Roommate]? = []

    @Relationship(deleteRule: .cascade, inverse: \Chore.household)
    var chores: [Chore]? = []

    @Relationship(deleteRule: .cascade, inverse: \Assignment.household)
    var assignments: [Assignment]? = []

    init(name: String = "Our place", cycleLengthDays: Int = 7) {
        self.id = UUID()
        self.name = name
        self.cycleLengthDays = cycleLengthDays
        self.cycleStartDate = Calendar.current.startOfDay(for: Date())
        self.setupStageRaw = SetupStage.household.rawValue
    }

    var setupStage: SetupStage {
        get { SetupStage(rawValue: setupStageRaw) ?? .household }
        set { setupStageRaw = newValue.rawValue }
    }

    var sortedMembers: [Roommate] {
        (members ?? []).sorted { $0.joinedAt < $1.joinedAt }
    }

    var activeChores: [Chore] {
        (chores ?? []).filter(\.isActive).sorted { $0.title < $1.title }
    }

    // MARK: - Cycle maths

    /// End of the cycle currently in progress.
    var cycleEndDate: Date {
        Calendar.current.date(byAdding: .day, value: cycleLengthDays, to: currentCycleStart) ?? Date()
    }

    /// Start of the cycle we are in right now, rolling forward from `cycleStartDate`
    /// however many whole cycles have elapsed.
    var currentCycleStart: Date {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: cycleStartDate, to: Date()).day ?? 0
        guard days >= cycleLengthDays, cycleLengthDays > 0 else { return cycleStartDate }
        let elapsed = (days / cycleLengthDays) * cycleLengthDays
        return calendar.date(byAdding: .day, value: elapsed, to: cycleStartDate) ?? cycleStartDate
    }

    /// Assignments belonging to the cycle in progress.
    var currentCycleAssignments: [Assignment] {
        let start = currentCycleStart
        let end = cycleEndDate
        return (assignments ?? []).filter { $0.assignedAt >= start && $0.assignedAt < end }
    }
}
