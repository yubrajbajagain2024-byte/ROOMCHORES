import Foundation

// Row types matching the tables and functions in supabase/migrations. Column names are
// snake_case on the server, so every type spells its keys out.

struct ProfileRow: Codable, Equatable, Sendable {
    let id: UUID
    var displayName: String
    var emoji: String

    enum CodingKeys: String, CodingKey {
        case id, emoji
        case displayName = "display_name"
    }
}

struct GroupRow: Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var cycleLengthDays: Int
    var cycleStartDate: Date
    var setupStage: String
    var fairnessTolerance: Double
    var minimumRatingsToReveal: Int
    var ratingWindowHours: Int
    var autoAssignEnabled: Bool
    var inviteCode: String
    var createdBy: UUID

    enum CodingKeys: String, CodingKey {
        case id, name
        case cycleLengthDays = "cycle_length_days"
        case cycleStartDate = "cycle_start_date"
        case setupStage = "setup_stage"
        case fairnessTolerance = "fairness_tolerance"
        case minimumRatingsToReveal = "minimum_ratings_to_reveal"
        case ratingWindowHours = "rating_window_hours"
        case autoAssignEnabled = "auto_assign_enabled"
        case inviteCode = "invite_code"
        case createdBy = "created_by"
    }
}

/// The group settings a member may change. Invite codes and ownership only change through
/// the database functions.
struct GroupUpdate: Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var cycleLengthDays: Int
    var cycleStartDate: Date
    var setupStage: String

    /// The request body — the id selects the row rather than being written.
    var editableFields: GroupEdit {
        GroupEdit(name: name, cycleLengthDays: cycleLengthDays, cycleStartDate: cycleStartDate, setupStage: setupStage)
    }
}

struct GroupEdit: Encodable, Sendable {
    let name: String
    let cycleLengthDays: Int
    let cycleStartDate: Date
    let setupStage: String

    enum CodingKeys: String, CodingKey {
        case name
        case cycleLengthDays = "cycle_length_days"
        case cycleStartDate = "cycle_start_date"
        case setupStage = "setup_stage"
    }
}

struct MemberRow: Codable, Equatable, Sendable {
    let groupId: UUID
    let userId: UUID
    var role: String
    var shareWeight: Double
    var carryOverPoints: Double
    var paletteIndex: Int
    var joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case role
        case groupId = "group_id"
        case userId = "user_id"
        case shareWeight = "share_weight"
        case carryOverPoints = "carry_over_points"
        case paletteIndex = "palette_index"
        case joinedAt = "joined_at"
    }
}

struct ChoreRow: Codable, Equatable, Sendable {
    let id: UUID
    let groupId: UUID
    var title: String
    var notes: String
    var category: String
    var recurrence: String
    var isActive: Bool
    var proposerId: UUID?
    var proposedDifficulty: Int
    var proposedLabor: Int
    var proposedMinutes: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title, notes, category, recurrence
        case groupId = "group_id"
        case isActive = "is_active"
        case proposerId = "proposer_id"
        case proposedDifficulty = "proposed_difficulty"
        case proposedLabor = "proposed_labor"
        case proposedMinutes = "proposed_minutes"
        case createdAt = "created_at"
    }

    /// Fields any member may edit. Who proposed a chore, and which group it's in, never change.
    var editableFields: ChoreEdit {
        ChoreEdit(title: title, notes: notes, category: category, recurrence: recurrence,
                  isActive: isActive, proposedDifficulty: proposedDifficulty,
                  proposedLabor: proposedLabor, proposedMinutes: proposedMinutes)
    }
}

struct ChoreEdit: Encodable, Sendable {
    let title: String
    let notes: String
    let category: String
    let recurrence: String
    let isActive: Bool
    let proposedDifficulty: Int
    let proposedLabor: Int
    let proposedMinutes: Int

    enum CodingKeys: String, CodingKey {
        case title, notes, category, recurrence
        case isActive = "is_active"
        case proposedDifficulty = "proposed_difficulty"
        case proposedLabor = "proposed_labor"
        case proposedMinutes = "proposed_minutes"
    }
}

struct AssignmentRow: Codable, Equatable, Sendable {
    let id: UUID
    let groupId: UUID
    var choreId: UUID?
    var assigneeId: UUID?
    var assignedAt: Date
    var dueDate: Date
    var status: String
    var pointsQuoted: Int
    var awardedPoints: Double?
    var completedAt: Date?
    var wasAutoAssigned: Bool
    var assignmentReason: String
    var proofVideoPath: String?
    var proofVideoDuration: Double?

    enum CodingKeys: String, CodingKey {
        case id, status
        case groupId = "group_id"
        case choreId = "chore_id"
        case assigneeId = "assignee_id"
        case assignedAt = "assigned_at"
        case dueDate = "due_date"
        case pointsQuoted = "points_quoted"
        case awardedPoints = "awarded_points"
        case completedAt = "completed_at"
        case wasAutoAssigned = "was_auto_assigned"
        case assignmentReason = "assignment_reason"
        case proofVideoPath = "proof_video_path"
        case proofVideoDuration = "proof_video_duration"
    }

    // Optionals are written as explicit nulls, so clearing a video path actually clears it.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(groupId, forKey: .groupId)
        try c.encode(choreId, forKey: .choreId)
        try c.encode(assigneeId, forKey: .assigneeId)
        try c.encode(assignedAt, forKey: .assignedAt)
        try c.encode(dueDate, forKey: .dueDate)
        try c.encode(status, forKey: .status)
        try c.encode(pointsQuoted, forKey: .pointsQuoted)
        try c.encode(awardedPoints, forKey: .awardedPoints)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(wasAutoAssigned, forKey: .wasAutoAssigned)
        try c.encode(assignmentReason, forKey: .assignmentReason)
        try c.encode(proofVideoPath, forKey: .proofVideoPath)
        try c.encode(proofVideoDuration, forKey: .proofVideoDuration)
    }
}

struct ValueSummaryRow: Codable, Equatable, Sendable {
    let choreId: UUID
    let voteCount: Int
    let avgDifficulty: Double?
    let avgLabor: Double?
    let avgMinutes: Double?

    enum CodingKeys: String, CodingKey {
        case choreId = "chore_id"
        case voteCount = "vote_count"
        case avgDifficulty = "avg_difficulty"
        case avgLabor = "avg_labor"
        case avgMinutes = "avg_minutes"
    }
}

struct RatingSummaryRow: Codable, Equatable, Sendable {
    let assignmentId: UUID
    let ratingCount: Int
    /// `nil` until enough ratings are in to show it without identifying anyone.
    let averageScore: Double?
    let notes: [String]?

    enum CodingKeys: String, CodingKey {
        case notes
        case assignmentId = "assignment_id"
        case ratingCount = "rating_count"
        case averageScore = "average_score"
    }
}

struct MyVoteRow: Codable, Equatable, Sendable {
    let choreId: UUID
    let difficulty: Int
    let labor: Int
    let minutes: Int

    enum CodingKeys: String, CodingKey {
        case difficulty, labor, minutes
        case choreId = "chore_id"
    }
}

struct MyRatingRow: Codable, Equatable, Sendable {
    let assignmentId: UUID
    let score: Int
    let note: String

    enum CodingKeys: String, CodingKey {
        case score, note
        case assignmentId = "assignment_id"
    }
}

struct InvitePreview: Codable, Equatable, Sendable {
    let groupId: UUID
    let groupName: String
    let memberCount: Int
    let alreadyMember: Bool

    enum CodingKeys: String, CodingKey {
        case groupId = "group_id"
        case groupName = "group_name"
        case memberCount = "member_count"
        case alreadyMember = "already_member"
    }
}

/// Everything one phone needs to show a group, fetched in one go.
struct GroupSnapshot: Equatable, Sendable {
    var group: GroupRow
    var members: [MemberRow]
    var profiles: [ProfileRow]
    var chores: [ChoreRow]
    var valueSummaries: [ValueSummaryRow]
    var myVotes: [MyVoteRow]
    var assignments: [AssignmentRow]
    var ratingSummaries: [RatingSummaryRow]
    var myRatings: [MyRatingRow]
}
