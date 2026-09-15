import Foundation

// Local models → rows the server stores.

extension ChoreRow {
    init(chore: Chore, groupID: UUID) {
        self.init(
            id: chore.id,
            groupId: groupID,
            title: chore.title,
            notes: chore.notes,
            category: chore.category.rawValue,
            recurrence: chore.recurrence.rawValue,
            isActive: chore.isActive,
            proposerId: chore.proposerID,
            proposedDifficulty: chore.proposedDifficulty,
            proposedLabor: chore.proposedLabor,
            proposedMinutes: chore.proposedMinutes,
            createdAt: chore.createdAt
        )
    }
}

extension AssignmentRow {
    init(assignment: Assignment, groupID: UUID) {
        self.init(
            id: assignment.id,
            groupId: groupID,
            choreId: assignment.chore?.id,
            assigneeId: assignment.assignee?.id,
            assignedAt: assignment.assignedAt,
            dueDate: assignment.dueDate,
            status: assignment.status.rawValue,
            pointsQuoted: assignment.pointsQuoted,
            awardedPoints: assignment.awardedPoints,
            completedAt: assignment.completedAt,
            wasAutoAssigned: assignment.wasAutoAssigned,
            assignmentReason: String(assignment.assignmentReason.prefix(200)),
            proofVideoPath: assignment.proofVideoRemotePath,
            proofVideoDuration: assignment.proofVideoDuration
        )
    }
}

extension GroupUpdate {
    init(household: Household) {
        self.init(
            id: household.id,
            name: household.name,
            cycleLengthDays: household.cycleLengthDays,
            cycleStartDate: household.cycleStartDate,
            setupStage: household.setupStage == .running ? "running" : "choreBuilding"
        )
    }
}
