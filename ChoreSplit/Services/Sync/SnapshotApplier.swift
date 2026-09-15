import Foundation
import SwiftData

/// Makes the phone's copy of a group match what the server sent.
///
/// Objects are updated in place rather than replaced, so anything that only lives on this
/// phone survives a refresh: reminders, the proof video file, and the salts used to recognise
/// your own anonymous ratings. Chores and tasks with changes still waiting to be sent are left
/// alone until those changes go through.
enum SnapshotApplier {

    struct Outcome: Equatable {
        /// Settled tasks of yours whose uploaded video can now be deleted.
        var expiredVideoPaths: [(assignmentID: UUID, path: String)] = []
        /// Tasks given to you on another phone, which need a reminder on this one.
        var newTasksForMe: [UUID] = []

        static func == (lhs: Outcome, rhs: Outcome) -> Bool {
            lhs.expiredVideoPaths.map(\.path) == rhs.expiredVideoPaths.map(\.path)
                && lhs.newTasksForMe == rhs.newTasksForMe
        }
    }

    @discardableResult
    static func apply(
        _ snapshot: GroupSnapshot,
        currentUserID: UUID,
        protectedIDs: Set<UUID> = [],
        context: ModelContext
    ) throws -> Outcome {
        var outcome = Outcome()
        let household = try household(for: snapshot.group, context: context)

        // Members
        let profiles = Dictionary(snapshot.profiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var roommates = Dictionary((household.members ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let memberIDs = Set(snapshot.members.map(\.userId))

        for row in snapshot.members {
            let roommate = roommates[row.userId] ?? {
                let created = Roommate(name: "")
                created.id = row.userId
                created.household = household
                context.insert(created)
                roommates[row.userId] = created
                return created
            }()
            let profile = profiles[row.userId]
            roommate.name = profile?.displayName ?? "Roommate"
            roommate.emoji = profile?.emoji ?? "🙂"
            roommate.role = row.role
            roommate.paletteIndex = row.paletteIndex
            roommate.shareWeight = row.shareWeight
            roommate.carryOverPoints = row.carryOverPoints
            roommate.joinedAt = row.joinedAt
        }
        for (id, roommate) in roommates where !memberIDs.contains(id) {
            context.delete(roommate)
            roommates[id] = nil
        }

        // Chores
        let valueSummaries = Dictionary(snapshot.valueSummaries.map { ($0.choreId, $0) }, uniquingKeysWith: { first, _ in first })
        var chores = Dictionary((household.chores ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteChoreIDs = Set(snapshot.chores.map(\.id))

        for row in snapshot.chores {
            if let existing = chores[row.id], protectedIDs.contains(row.id) {
                applySummary(valueSummaries[row.id], to: existing)
                continue
            }
            let chore = chores[row.id] ?? {
                let created = Chore(title: row.title)
                created.id = row.id
                created.household = household
                context.insert(created)
                chores[row.id] = created
                return created
            }()
            chore.title = row.title
            chore.notes = row.notes
            chore.categoryRaw = row.category
            chore.recurrenceRaw = row.recurrence
            chore.isActive = row.isActive
            chore.proposerID = row.proposerId
            chore.proposedDifficulty = row.proposedDifficulty
            chore.proposedLabor = row.proposedLabor
            chore.proposedMinutes = row.proposedMinutes
            chore.createdAt = row.createdAt
            applySummary(valueSummaries[row.id], to: chore)
        }
        for (id, chore) in chores where !remoteChoreIDs.contains(id) && !protectedIDs.contains(id) {
            context.delete(chore)
            chores[id] = nil
        }

        for vote in snapshot.myVotes {
            guard let chore = chores[vote.choreId] else { continue }
            let token = AnonymityService.token(for: currentUserID, salt: chore.anonymitySalt)
            guard !chore.votes.contains(where: { $0.raterToken == token }) else { continue }
            let local = ChoreValueVote(raterToken: token, difficulty: vote.difficulty, labor: vote.labor, minutes: vote.minutes)
            local.chore = chore
            context.insert(local)
        }

        // Assignments
        let ratingSummaries = Dictionary(snapshot.ratingSummaries.map { ($0.assignmentId, $0) }, uniquingKeysWith: { first, _ in first })
        var assignments = Dictionary((household.assignments ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let remoteAssignmentIDs = Set(snapshot.assignments.map(\.id))

        for row in snapshot.assignments {
            if let existing = assignments[row.id], protectedIDs.contains(row.id) {
                applySummary(ratingSummaries[row.id], to: existing)
                continue
            }
            let isNew = assignments[row.id] == nil
            let assignment = assignments[row.id] ?? {
                let created = Assignment(remoteID: row.id)
                created.household = household
                context.insert(created)
                assignments[row.id] = created
                return created
            }()

            assignment.chore = row.choreId.flatMap { chores[$0] }
            assignment.assignee = row.assigneeId.flatMap { roommates[$0] }
            assignment.assignedAt = row.assignedAt
            assignment.dueDate = row.dueDate
            assignment.statusRaw = row.status
            assignment.pointsQuoted = row.pointsQuoted
            assignment.awardedPoints = row.awardedPoints
            assignment.completedAt = row.completedAt
            assignment.wasAutoAssigned = row.wasAutoAssigned
            assignment.assignmentReason = row.assignmentReason
            assignment.proofVideoRemotePath = row.proofVideoPath
            if let duration = row.proofVideoDuration {
                assignment.proofVideoDuration = duration
            }
            applySummary(ratingSummaries[row.id], to: assignment)

            if assignment.status == .settled {
                if let filename = assignment.proofVideoFilename {
                    ProofVideoStore.delete(filename: filename)
                    assignment.proofVideoFilename = nil
                }
                // The person who uploaded the video tidies it away.
                if let path = row.proofVideoPath, row.assigneeId == currentUserID {
                    outcome.expiredVideoPaths.append((row.id, path))
                }
            }

            if isNew, row.assigneeId == currentUserID, assignment.status == .open {
                outcome.newTasksForMe.append(row.id)
            }
        }
        for (id, assignment) in assignments where !remoteAssignmentIDs.contains(id) && !protectedIDs.contains(id) {
            context.delete(assignment)
            assignments[id] = nil
        }

        for rating in snapshot.myRatings {
            guard let assignment = assignments[rating.assignmentId] else { continue }
            let token = AnonymityService.token(for: currentUserID, salt: assignment.anonymitySalt)
            guard !assignment.ratings.contains(where: { $0.raterToken == token }) else { continue }
            let local = QualityRating(raterToken: token, score: rating.score, note: rating.note)
            local.assignment = assignment
            context.insert(local)
        }

        household.lastSyncedAt = Date()
        try context.save()
        return outcome
    }

    // MARK: - Pieces

    private static func household(for row: GroupRow, context: ModelContext) throws -> Household {
        let groupID = row.id
        let existing = try context.fetch(FetchDescriptor<Household>(predicate: #Predicate { $0.id == groupID })).first
        let household = existing ?? {
            let created = Household(name: row.name, cycleLengthDays: row.cycleLengthDays)
            created.id = row.id
            created.isShared = true
            context.insert(created)
            return created
        }()

        household.isShared = true
        household.name = row.name
        household.cycleLengthDays = row.cycleLengthDays
        household.cycleStartDate = row.cycleStartDate
        household.setupStage = row.setupStage == "running" ? .running : .choreBuilding
        household.fairnessTolerance = row.fairnessTolerance
        household.minimumRatingsToReveal = row.minimumRatingsToReveal
        household.ratingWindowHours = row.ratingWindowHours
        household.autoAssignEnabled = row.autoAssignEnabled
        household.inviteCode = row.inviteCode
        return household
    }

    private static func applySummary(_ summary: ValueSummaryRow?, to chore: Chore) {
        chore.remoteVoteCount = summary?.voteCount ?? 0
        chore.remoteAverageDifficulty = summary?.avgDifficulty
        chore.remoteAverageLabor = summary?.avgLabor
        chore.remoteAverageMinutes = summary?.avgMinutes
    }

    private static func applySummary(_ summary: RatingSummaryRow?, to assignment: Assignment) {
        assignment.remoteRatingCount = summary?.ratingCount ?? 0
        assignment.remoteAverageScore = summary?.averageScore
        assignment.remoteNotes = summary?.notes
    }
}
