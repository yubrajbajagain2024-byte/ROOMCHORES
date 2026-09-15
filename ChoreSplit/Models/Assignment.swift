import Foundation
import SwiftData

@Model
final class Assignment {
    var id: UUID = UUID()
    var assignedAt: Date = Date()
    var dueDate: Date = Date()
    var statusRaw: String = AssignmentStatus.open.rawValue

    /// Points locked in at the moment of assignment. Later re-ratings of the chore
    /// change what it is worth *next* time — they never silently rewrite what you
    /// already agreed to take on.
    var pointsQuoted: Int = 0

    /// Final points banked once peer ratings close. `nil` while still in flight.
    var awardedPoints: Double?

    var completedAt: Date?

    /// True when the fairness engine handed this out rather than someone claiming it.
    var wasAutoAssigned: Bool = false

    /// Plain-language note explaining why this landed on this person, e.g.
    /// "14 points below your share this cycle".
    var assignmentReason: String = ""

    // MARK: - Voice reminder

    var reminderDate: Date?
    var voiceReminderEnabled: Bool = true
    /// The sentence that gets spoken. Generated from the chore, editable by the user.
    var reminderSpokenText: String = ""

    // MARK: - Proof video

    /// The video the assignee attached to show the task was done, stored by `ProofVideoStore`.
    /// Cleared, and the file deleted, once ratings close.
    var proofVideoFilename: String?
    var proofVideoDuration: Double?

    /// Where the proof video lives on the server, once uploaded.
    var proofVideoRemotePath: String?

    // MARK: - Server totals (shared groups)
    //
    // Only your own rating is ever on the phone. The count, and — once enough people have
    // rated — the average and notes, come from the server.
    var remoteRatingCount: Int?
    var remoteAverageScore: Double?
    var remoteNotes: [String]?

    /// Per-assignment salt for hashing quality-rater identities.
    var anonymitySalt: Data = Data()

    var chore: Chore?
    var assignee: Roommate?
    var household: Household?

    @Relationship(deleteRule: .cascade, inverse: \QualityRating.assignment)
    var qualityRatings: [QualityRating]? = []

    init(
        chore: Chore,
        assignee: Roommate,
        dueDate: Date,
        wasAutoAssigned: Bool = false,
        assignmentReason: String = ""
    ) {
        self.id = UUID()
        self.chore = chore
        self.assignee = assignee
        self.dueDate = dueDate
        self.assignedAt = Date()
        self.pointsQuoted = chore.points
        self.wasAutoAssigned = wasAutoAssigned
        self.assignmentReason = assignmentReason
        self.statusRaw = AssignmentStatus.open.rawValue
        self.anonymitySalt = AnonymityService.newSalt()
        self.reminderSpokenText = ""
    }

    /// An assignment arriving from the server. The sync layer fills in the rest.
    init(remoteID: UUID) {
        self.id = remoteID
        self.anonymitySalt = AnonymityService.newSalt()
        self.statusRaw = AssignmentStatus.open.rawValue
        self.reminderSpokenText = ""
    }

    var status: AssignmentStatus {
        get { AssignmentStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }

    var title: String { chore?.title ?? "Chore" }

    /// The proof video on disk, if there is one and it still exists.
    var proofVideoURL: URL? {
        proofVideoFilename.flatMap(ProofVideoStore.existingURL(for:))
    }
    var ratings: [QualityRating] { qualityRatings ?? [] }

    // MARK: - Points

    /// Points this assignment currently contributes to the assignee's total —
    /// provisional while open, final once settled.
    var effectivePoints: Double {
        switch status {
        case .settled:        return awardedPoints ?? Double(pointsQuoted)
        case .skipped:        return 0
        case .open, .awaitingReview: return Double(pointsQuoted)
        }
    }

    /// Whether these points are still subject to change.
    var pointsAreProvisional: Bool {
        status == .open || status == .awaitingReview
    }

    /// The true average of the ratings on this phone. Used to settle points in the demo
    /// household; shared groups are settled by the server.
    var averageQuality: Double? {
        guard !ratings.isEmpty else { return nil }
        return ratings.map { Double($0.score) }.average
    }

    /// How many people have rated this task so far.
    var ratingCount: Int { remoteRatingCount ?? ratings.count }

    /// Quality scores stay hidden until enough raters are in.
    func qualityIsRevealed(in household: Household?) -> Bool {
        ratingCount >= (household?.minimumRatingsToReveal ?? 2)
    }

    /// The average rating, or `nil` while too few are in to show it anonymously.
    func revealedAverage(in household: Household?) -> Double? {
        guard qualityIsRevealed(in: household) else { return nil }
        return remoteRatingCount != nil ? remoteAverageScore : averageQuality
    }

    /// Anonymous notes, once enough ratings are in — sorted, so their order gives nothing away.
    func revealedNotes(in household: Household?) -> [String] {
        guard qualityIsRevealed(in: household) else { return [] }
        let notes = remoteRatingCount != nil ? (remoteNotes ?? []) : ratings.map(\.note)
        return notes.filter { !$0.isEmpty }.sorted()
    }

    /// The video to play: the file on this phone if there is one, otherwise the uploaded copy.
    var hasProofVideo: Bool { proofVideoURL != nil || proofVideoRemotePath != nil }

    func hasRated(_ roommate: Roommate) -> Bool {
        let token = AnonymityService.token(for: roommate.id, salt: anonymitySalt)
        return ratings.contains { $0.raterToken == token }
    }

    /// Roommates other than the person who did the work — the eligible raters.
    func eligibleRaters(in household: Household) -> [Roommate] {
        household.sortedMembers.filter { $0.id != assignee?.id }
    }

    /// When peer rating closes and points become final.
    func ratingDeadline(in household: Household) -> Date? {
        guard let completedAt else { return nil }
        return Calendar.current.date(byAdding: .hour, value: household.ratingWindowHours, to: completedAt)
    }

    // MARK: - Timing

    var isOverdue: Bool {
        status == .open && dueDate < Date()
    }

    var isDueToday: Bool {
        Calendar.current.isDateInToday(dueDate)
    }

    var dueDescription: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) { return "Today" }
        if calendar.isDateInTomorrow(dueDate) { return "Tomorrow" }
        if calendar.isDateInYesterday(dueDate) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.dateFormat = dueDate.isInSameYear(as: Date()) ? "EEE d MMM" : "d MMM yyyy"
        return formatter.string(from: dueDate)
    }
}

@Model
final class QualityRating {
    var id: UUID = UUID()
    /// Salted hash of the rater's ID — stops double-rating, never shown in the UI.
    var raterToken: String = ""
    /// 1–5: how well the job was actually done.
    var score: Int = 3
    /// Optional anonymous note, shown to the assignee without attribution.
    var note: String = ""
    var createdAt: Date = Date()

    var assignment: Assignment?

    init(raterToken: String, score: Int, note: String = "") {
        self.id = UUID()
        self.raterToken = raterToken
        self.score = score
        self.note = note
        self.createdAt = Date()
    }
}

extension Date {
    func isInSameYear(as other: Date) -> Bool {
        Calendar.current.component(.year, from: self) == Calendar.current.component(.year, from: other)
    }
}
