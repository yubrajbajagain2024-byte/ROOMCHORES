import Foundation
import SwiftData

/// Every state change that matters, in one place.
///
/// These are the operations the rules actually live in: completing work, banking points
/// once peers have rated, and handing extra chores to whoever has fallen behind.
/// Receives every change that should reach the server. Set while a shared group is open;
/// `nil` for the on-device demo household, where nothing leaves the phone.
protocol HouseholdSyncing: AnyObject {
    /// The signed-in person on this phone.
    var currentUserID: UUID { get }
    func choreChanged(_ chore: Chore)
    func assignmentChanged(_ assignment: Assignment)
    func valueVoteCast(on chore: Chore, difficulty: Int, labor: Int, minutes: Int)
    func qualityRated(_ assignment: Assignment, score: Int, note: String)
    func memberChanged(_ roommate: Roommate)
    func householdChanged(_ household: Household)
    func proofVideoExpired(path: String)
}

enum HouseholdActions {

    /// Where changes go to be synced. Weak, so a closed group's engine isn't kept alive.
    static weak var sync: HouseholdSyncing?

    /// Whether this phone should remind someone about a task. In a shared group a reminder
    /// belongs on the phone of the person doing it — theirs schedules it when the task arrives —
    /// otherwise your phone would announce "Priya, the bins are due" out loud. On the demo's
    /// shared phone, everyone's reminders go here.
    static func remindsOnThisPhone(for roommate: Roommate, in household: Household) -> Bool {
        !household.isShared || sync?.currentUserID == roommate.id
    }

    // MARK: - Doing chores

    /// Mark a chore done. Points are not banked yet — they wait on peer ratings, which is
    /// what stops "done" meaning "shoved in a cupboard".
    static func markComplete(_ assignment: Assignment, in household: Household, context: ModelContext) {
        assignment.completedAt = Date()
        assignment.status = .awaitingReview

        let assignmentID = assignment.id
        Task { await NotificationService.shared.cancelReminder(assignmentID: assignmentID) }

        // A one-off task is finished for good. Leaving it active would let the catch-up
        // planner hand the same errand out again next time someone falls behind.
        if let chore = assignment.chore, chore.recurrence == .once {
            chore.isActive = false
            sync?.choreChanged(chore)
        }
        sync?.assignmentChanged(assignment)

        // In a one-person household — or when nobody else can rate — there is nothing to
        // wait for, so settle at full points immediately.
        if assignment.eligibleRaters(in: household).isEmpty {
            settle(assignment)
        } else if let deadline = assignment.ratingDeadline(in: household) {
            let title = assignment.title
            let id = assignment.id
            Task {
                await NotificationService.shared.scheduleRatingNudge(
                    assignmentTitle: title, at: deadline, assignmentID: id
                )
            }
        }

        queueNextOccurrence(of: assignment, in: household, context: context)
        try? context.save()
    }

    static func markSkipped(_ assignment: Assignment, context: ModelContext) {
        assignment.status = .skipped
        assignment.awardedPoints = 0
        sync?.assignmentChanged(assignment)
        let assignmentID = assignment.id
        Task { await NotificationService.shared.cancelReminder(assignmentID: assignmentID) }
        try? context.save()
    }

    /// Bank the final points for a completed chore.
    static func settle(_ assignment: Assignment) {
        assignment.awardedPoints = PointsEngine.settledPoints(
            quoted: assignment.pointsQuoted,
            averageQuality: assignment.averageQuality
        )
        assignment.status = .settled

        // The video was there so roommates could judge the work. With ratings closed its job
        // is done, and keeping a clip per chore would slowly fill a shared phone.
        if let filename = assignment.proofVideoFilename {
            ProofVideoStore.delete(filename: filename)
            assignment.proofVideoFilename = nil
            assignment.proofVideoDuration = nil
        }
        if let path = assignment.proofVideoRemotePath {
            sync?.proofVideoExpired(path: path)
            assignment.proofVideoRemotePath = nil
            sync?.assignmentChanged(assignment)
        }
    }

    // MARK: - Anonymous ratings

    /// Rate how well a completed chore was done. Stored against a salted hash, never a name.
    static func submitQualityRating(
        for assignment: Assignment,
        by rater: Roommate,
        score: Int,
        note: String = "",
        in household: Household,
        context: ModelContext
    ) {
        guard !assignment.hasRated(rater) else { return }

        let rating = QualityRating(
            raterToken: AnonymityService.token(for: rater.id, salt: assignment.anonymitySalt),
            score: score,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        rating.assignment = assignment
        context.insert(rating)
        sync?.qualityRated(assignment, score: score, note: rating.note)

        // Once everyone entitled to rate has done so, there is nothing left to wait for.
        let raters = assignment.eligibleRaters(in: household)
        if raters.allSatisfy({ assignment.hasRated($0) }) {
            settle(assignment)
        }
        try? context.save()
    }

    /// Rate what a chore is *worth*. This is the setup-time vote that sets point values,
    /// and it can be revisited later when the household decides a job was mispriced.
    static func submitValueVote(
        for chore: Chore,
        by rater: Roommate,
        difficulty: Int,
        labor: Int,
        minutes: Int,
        context: ModelContext
    ) {
        guard !chore.hasVoted(rater) else { return }
        let vote = ChoreValueVote(
            raterToken: AnonymityService.token(for: rater.id, salt: chore.anonymitySalt),
            difficulty: difficulty,
            labor: labor,
            minutes: minutes
        )
        vote.chore = chore
        context.insert(vote)
        sync?.valueVoteCast(on: chore, difficulty: difficulty, labor: labor, minutes: minutes)
        try? context.save()
    }

    // MARK: - Assigning

    @discardableResult
    static func assign(
        chore: Chore,
        to roommate: Roommate,
        due: Date,
        in household: Household,
        context: ModelContext,
        autoAssigned: Bool = false,
        reason: String = "",
        scheduleReminder: Bool = true
    ) -> Assignment {
        let assignment = Assignment(
            chore: chore,
            assignee: roommate,
            dueDate: due,
            wasAutoAssigned: autoAssigned,
            assignmentReason: reason
        )
        assignment.household = household
        assignment.reminderSpokenText = ReminderPhrase.sentence(for: assignment, assigneeName: roommate.name)
        assignment.reminderDate = defaultReminderDate(for: due)
        context.insert(assignment)
        sync?.assignmentChanged(assignment)

        if scheduleReminder, remindsOnThisPhone(for: roommate, in: household) {
            let reminder = NotificationService.ReminderRequest(assignment: assignment, assigneeName: roommate.name)
            Task { await NotificationService.shared.scheduleReminder(reminder) }
        }
        try? context.save()
        return assignment
    }

    static func apply(_ proposals: [ProposedAssignment], in household: Household, context: ModelContext) {
        var reminders: [NotificationService.ReminderRequest] = []
        for proposal in proposals {
            let assignment = assign(
                chore: proposal.chore,
                to: proposal.roommate,
                due: proposal.dueDate,
                in: household,
                context: context,
                autoAssigned: true,
                reason: proposal.reason,
                // Reminders are scheduled below instead, one at a time.
                scheduleReminder: false
            )
            if remindsOnThisPhone(for: proposal.roommate, in: household) {
                reminders.append(NotificationService.ReminderRequest(assignment: assignment, assigneeName: proposal.roommate.name))
            }
        }

        // A rebalance can hand out a dozen chores at once. Each voice reminder means
        // running the speech synthesiser, so they go through in sequence — firing a dozen
        // synthesisers concurrently is enough to take the app down.
        Task {
            for reminder in reminders {
                await NotificationService.shared.scheduleReminder(reminder)
            }
        }
    }

    /// Reminders default to two hours before the chore is due — long enough to act on,
    /// close enough that it has not been forgotten again by the time it matters.
    static func defaultReminderDate(for dueDate: Date) -> Date? {
        let candidate = Calendar.current.date(byAdding: .hour, value: -2, to: dueDate) ?? dueDate
        return candidate > Date() ? candidate : nil
    }

    /// Put a recurring chore back on the board once it has been done.
    private static func queueNextOccurrence(
        of assignment: Assignment,
        in household: Household,
        context: ModelContext
    ) {
        guard let chore = assignment.chore,
              chore.isActive,
              let interval = chore.recurrence.intervalDays
        else { return }

        let nextDue = Calendar.current.date(byAdding: .day, value: interval, to: assignment.dueDate)
            ?? Date().addingTimeInterval(Double(interval) * 86_400)

        // Don't queue work past the end of the cycle — the next roll will place it fairly.
        guard nextDue < household.cycleEndDate else { return }

        // Whoever is furthest behind takes the next turn. This is the core rule: the
        // rota is not a fixed rotation, it follows the points.
        guard let next = FairnessEngine.nextInLine(for: household) else { return }
        assign(
            chore: chore,
            to: next,
            due: nextDue,
            in: household,
            context: context,
            autoAssigned: true,
            reason: "Next turn — lowest points in the household"
        )
    }

    // MARK: - Maintenance

    /// A chore was created or edited in a view.
    static func choreSaved(_ chore: Chore) {
        sync?.choreChanged(chore)
    }

    /// Group-level settings changed, such as setup finishing.
    static func householdSaved(_ household: Household) {
        sync?.householdChanged(household)
    }

    /// Housekeeping run on launch and whenever the app comes back to the foreground:
    /// close expired rating windows, roll the cycle, and top up anyone who has fallen behind.
    ///
    /// In a shared group the server settles ratings, so `settlesLocally` is false there.
    static func runMaintenance(for household: Household, context: ModelContext, settlesLocally: Bool = true) {
        let now = Date()

        // 1. Settle anything whose rating window has closed.
        if settlesLocally {
            for assignment in (household.assignments ?? []) where assignment.status == .awaitingReview {
                if let deadline = assignment.ratingDeadline(in: household), deadline <= now {
                    settle(assignment)
                }
            }
        }

        // 2. Write off chores that were never done and are now a full cycle stale.
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -household.cycleLengthDays, to: now) ?? now
        for assignment in (household.assignments ?? [])
        where assignment.status == .open && assignment.dueDate < staleCutoff {
            assignment.status = .skipped
            assignment.awardedPoints = 0
            sync?.assignmentChanged(assignment)
        }

        // 3. Roll the cycle if we have passed its end, carrying half of any imbalance forward.
        if now >= household.cycleEndDate {
            FairnessEngine.rollCycle(for: household)
            household.sortedMembers.forEach { sync?.memberChanged($0) }
            sync?.householdChanged(household)
        }

        // 4. Hand catch-up chores to whoever is under their share.
        if household.autoAssignEnabled, household.setupStage == .running {
            let plan = FairnessEngine.catchUpPlan(for: household)
            apply(plan, in: household, context: context)
        }

        try? context.save()

        let stillBeingRated = Set((household.assignments ?? [])
            .filter { $0.status == .awaitingReview }
            .compactMap(\.proofVideoFilename))
        ProofVideoStore.prune(keeping: stillBeingRated)

        let liveIDs = Set((household.assignments ?? []).filter { $0.status == .open }.map(\.id))
        Task { await NotificationService.shared.pruneOrphans(activeAssignmentIDs: liveIDs) }
    }
}
