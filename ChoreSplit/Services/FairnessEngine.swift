import Foundation

/// Where one roommate stands against their fair share for the current cycle.
struct MemberStanding: Identifiable {
    let roommate: Roommate
    /// Points from chores that are finished and rated.
    var banked: Double
    /// Points from chores taken on but not yet settled.
    var provisional: Double
    /// Debt (positive) or credit (negative) rolled in from last cycle.
    var carryOver: Double
    /// What this person should be carrying, given their share weight and carry-over.
    var target: Double

    var id: UUID { roommate.id }

    /// Everything this person is currently carrying.
    var load: Double { banked + provisional }

    /// Positive means behind, negative means ahead.
    var deficit: Double { target - load }

    var percentOfTarget: Double {
        guard target > 0 else { return 1 }
        return load / target
    }

    func isBehind(tolerance: Double) -> Bool {
        guard target > 0 else { return false }
        return deficit > max(1, target * tolerance)
    }

    func isAhead(tolerance: Double) -> Bool {
        guard target > 0 else { return false }
        return -deficit > max(1, target * tolerance)
    }
}

/// A chore the engine proposes handing to someone, with the reason it picked them.
struct ProposedAssignment: Identifiable {
    let id = UUID()
    let chore: Chore
    let roommate: Roommate
    let dueDate: Date
    let reason: String
}

/// Works out who is pulling their weight and who needs handing more work.
///
/// Fairness is measured inside one cycle rather than over all time, so a bad week is
/// recoverable, and it is measured in *points* rather than chore count — three bin runs
/// do not equal one deep-cleaned bathroom.
enum FairnessEngine {

    // MARK: - Standings

    static func standings(for household: Household) -> [MemberStanding] {
        let members = household.sortedMembers
        guard !members.isEmpty else { return [] }

        let cycleAssignments = household.currentCycleAssignments.filter { $0.status != .skipped }

        var banked: [UUID: Double] = [:]
        var provisional: [UUID: Double] = [:]

        for assignment in cycleAssignments {
            guard let memberID = assignment.assignee?.id else { continue }
            if assignment.pointsAreProvisional {
                provisional[memberID, default: 0] += assignment.effectivePoints
            } else {
                banked[memberID, default: 0] += assignment.effectivePoints
            }
        }

        // The pool is the work actually on the table this cycle. Splitting the real
        // workload keeps targets honest: if the flat had a quiet week, nobody is judged
        // against an imaginary quota.
        let pool = cycleAssignments.reduce(0.0) { $0 + $1.effectivePoints }
        let totalWeight = members.reduce(0.0) { $0 + max(0.01, $1.shareWeight) }

        return members.map { member in
            let share = max(0.01, member.shareWeight) / totalWeight
            let baseTarget = pool * share
            return MemberStanding(
                roommate: member,
                banked: banked[member.id] ?? 0,
                provisional: provisional[member.id] ?? 0,
                carryOver: member.carryOverPoints,
                target: max(0, baseTarget + member.carryOverPoints)
            )
        }
    }


    // MARK: - Picking who is next

    /// Whoever is furthest below their fair share. This is the rule the whole app turns on:
    /// the next chore goes to the person carrying the least, not to whoever volunteers.
    static func nextInLine(for household: Household) -> Roommate? {
        standings(for: household)
            .max { $0.deficit < $1.deficit }?
            .roommate
    }

    /// Chores not currently sitting in someone's open list — fair game to hand out.
    static func availableChores(in household: Household) -> [Chore] {
        let openChoreIDs = Set(
            (household.assignments ?? [])
                .filter { $0.status == .open }
                .compactMap { $0.chore?.id }
        )
        return household.activeChores.filter { !openChoreIDs.contains($0.id) }
    }

    // MARK: - Catch-up assignments

    /// Extra chores for whoever has fallen behind.
    ///
    /// The subtlety is that handing someone a chore raises *everyone's* target, because the
    /// fair share is a slice of the work actually on the table. Assigning 12 points to one
    /// person in a three-person flat closes their gap by only 8 and opens a 4-point gap for
    /// each of the others. So the plan re-derives every deficit from the growing pool after
    /// each pick, rather than just subtracting from the one person — otherwise the app
    /// would keep finding someone "behind" on every launch and never stop handing out work.
    static func catchUpPlan(for household: Household, limitPerMember: Int = 3) -> [ProposedAssignment] {
        let members = household.sortedMembers
        guard !members.isEmpty else { return [] }

        let tolerance = household.fairnessTolerance
        let totalWeight = members.reduce(0.0) { $0 + max(0.01, $1.shareWeight) }

        var loads: [UUID: Double] = [:]
        var carryOver: [UUID: Double] = [:]
        for standing in standings(for: household) {
            loads[standing.roommate.id] = standing.load
            carryOver[standing.roommate.id] = standing.carryOver
        }
        var pool = loads.values.reduce(0, +)

        func target(_ member: Roommate) -> Double {
            let share = max(0.01, member.shareWeight) / totalWeight
            return max(0, pool * share + (carryOver[member.id] ?? 0))
        }
        func deficit(_ member: Roommate) -> Double {
            target(member) - (loads[member.id] ?? 0)
        }
        func isBehind(_ member: Roommate) -> Bool {
            let goal = target(member)
            return goal > 0 && deficit(member) > max(1, goal * tolerance)
        }

        var availablePool = availableChores(in: household).sorted { $0.points > $1.points }
        var proposals: [ProposedAssignment] = []
        var perMemberCount: [UUID: Int] = [:]
        /// People we have stopped trying to top up this round, so the loop always terminates.
        var exhausted: Set<UUID> = []

        while !availablePool.isEmpty {
            let candidates = members.filter {
                isBehind($0) && !exhausted.contains($0.id) && (perMemberCount[$0.id] ?? 0) < limitPerMember
            }
            guard let member = candidates.max(by: { deficit($0) < deficit($1) }) else { break }

            let gap = deficit(member)

            // Prefer the largest chore that fits inside the gap. If everything left is
            // bigger, only take the smallest when it does not wildly overshoot — dumping a
            // 40-point job on someone 5 points short just moves the unfairness along.
            let index: Int
            if let fitting = availablePool.firstIndex(where: { Double($0.points) <= gap }) {
                index = fitting
            } else if let smallest = availablePool.last, Double(smallest.points) <= gap * 1.5 {
                index = availablePool.count - 1
            } else {
                exhausted.insert(member.id)
                continue
            }

            let chore = availablePool.remove(at: index)
            proposals.append(
                ProposedAssignment(
                    chore: chore,
                    roommate: member,
                    dueDate: defaultDueDate(for: chore, in: household),
                    reason: reasonText(deficit: gap)
                )
            )

            loads[member.id, default: 0] += Double(chore.points)
            pool += Double(chore.points)
            perMemberCount[member.id, default: 0] += 1
        }

        return proposals
    }

    /// Spread every active chore across the household for a fresh cycle.
    ///
    /// Longest-processing-time-first: hand out the heaviest chores while there is still
    /// room to balance around them. Packing big jobs last is what produces the lopsided
    /// weeks this app exists to prevent.
    static func openingPlan(for household: Household) -> [ProposedAssignment] {
        let members = household.sortedMembers
        guard !members.isEmpty else { return [] }

        let totalWeight = members.reduce(0.0) { $0 + max(0.01, $1.shareWeight) }
        var loads: [UUID: Double] = [:]
        for standing in standings(for: household) {
            loads[standing.roommate.id] = standing.load
        }

        var proposals: [ProposedAssignment] = []
        let chores = availableChores(in: household).sorted { $0.points > $1.points }

        for chore in chores {
            // Pick the member whose load is furthest below their weighted share.
            let pick = members.min { a, b in
                let loadA = (loads[a.id] ?? 0) / (max(0.01, a.shareWeight) / totalWeight)
                let loadB = (loads[b.id] ?? 0) / (max(0.01, b.shareWeight) / totalWeight)
                return loadA < loadB
            }
            guard let member = pick else { continue }

            proposals.append(
                ProposedAssignment(
                    chore: chore,
                    roommate: member,
                    dueDate: defaultDueDate(for: chore, in: household),
                    reason: "Evenly split at the start of the cycle"
                )
            )
            loads[member.id, default: 0] += Double(chore.points)
        }

        return proposals
    }

    // MARK: - Helpers

    static func reasonText(deficit: Double) -> String {
        "\(Int(deficit.rounded())) points below your share this cycle"
    }

    /// Daily chores are due today; anything rarer gets breathing room, capped at the
    /// end of the cycle so nothing is due after the scoreboard resets.
    static func defaultDueDate(for chore: Chore, in household: Household) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let offsetDays: Int
        switch chore.recurrence {
        case .once:          offsetDays = 3
        case .daily:         offsetDays = 0
        case .everyOtherDay: offsetDays = 1
        case .weekly:        offsetDays = min(6, household.cycleLengthDays - 1)
        case .biweekly:      offsetDays = min(10, household.cycleLengthDays - 1)
        case .monthly:       offsetDays = min(14, household.cycleLengthDays - 1)
        }
        let due = calendar.date(byAdding: .day, value: max(0, offsetDays), to: today) ?? today
        // Due at 8pm — chores are evening work.
        return calendar.date(bySettingHour: 20, minute: 0, second: 0, of: due) ?? due
    }

    /// The most debt or credit that can follow someone into a new cycle — roughly three
    /// chores' worth on the 1–4 points scale.
    static let maximumCarryOver: Double = 10

    /// Roll the scoreboard into the next cycle, carrying unfinished balance forward so
    /// a lopsided week is not simply forgiven.
    static func rollCycle(for household: Household) {
        let current = standings(for: household)
        for standing in current {
            // Carry at most half the gap, capped at a few chores' worth, so debt cannot
            // spiral beyond recovery.
            let carried = (standing.deficit / 2).rounded()
            standing.roommate.carryOverPoints = max(-maximumCarryOver, min(maximumCarryOver, carried))
        }
        household.cycleStartDate = Calendar.current.startOfDay(for: Date())
    }
}
