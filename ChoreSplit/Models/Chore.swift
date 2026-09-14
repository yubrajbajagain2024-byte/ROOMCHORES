import Foundation
import SwiftData

@Model
final class Chore {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""
    var categoryRaw: String = ChoreCategory.other.rawValue
    var recurrenceRaw: String = Recurrence.weekly.rawValue
    var isActive: Bool = true
    var createdAt: Date = Date()

    /// Who added this chore during setup. Shown as "added by", but their *rating*
    /// of it is folded in anonymously alongside everyone else's.
    var proposerID: UUID?

    // MARK: - The proposer's own read of the job

    /// 1–5. How fiddly, unpleasant or skilled the job is.
    var proposedDifficulty: Int = 3
    /// 1–5. How physically hard it is — hauling, scrubbing, stairs.
    var proposedLabor: Int = 3
    /// Wall-clock minutes the job actually takes.
    var proposedMinutes: Int = 15

    /// Random per-chore salt. Rater identities are stored as a salted hash rather
    /// than a plain ID, so the vote table cannot be read back as "who said what"
    /// by glancing at the database. See `AnonymityService`.
    var anonymitySalt: Data = Data()

    var household: Household?

    @Relationship(deleteRule: .cascade, inverse: \ChoreValueVote.chore)
    var valueVotes: [ChoreValueVote]? = []

    @Relationship(deleteRule: .nullify, inverse: \Assignment.chore)
    var assignments: [Assignment]? = []

    init(
        title: String,
        notes: String = "",
        category: ChoreCategory = .other,
        recurrence: Recurrence = .weekly,
        difficulty: Int = 3,
        labor: Int = 3,
        minutes: Int = 15,
        proposerID: UUID? = nil
    ) {
        self.id = UUID()
        self.title = title
        self.notes = notes
        self.categoryRaw = category.rawValue
        self.recurrenceRaw = recurrence.rawValue
        self.proposedDifficulty = difficulty
        self.proposedLabor = labor
        self.proposedMinutes = minutes
        self.proposerID = proposerID
        self.createdAt = Date()
        self.isActive = true
        self.anonymitySalt = AnonymityService.newSalt()
    }

    var category: ChoreCategory {
        get { ChoreCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var recurrence: Recurrence {
        get { Recurrence(rawValue: recurrenceRaw) ?? .weekly }
        set { recurrenceRaw = newValue.rawValue }
    }

    var votes: [ChoreValueVote] { valueVotes ?? [] }

    // MARK: - Agreed values

    /// The household's shared read of this chore: the proposer's numbers averaged
    /// with every anonymous vote. One person cannot inflate their own chore, and a
    /// job everyone quietly agrees is grim drifts upward on its own.
    var agreedValues: ChoreValues {
        var difficulties = [Double(proposedDifficulty)]
        var labors = [Double(proposedLabor)]
        var minutes = [Double(proposedMinutes)]

        for vote in votes {
            difficulties.append(Double(vote.difficulty))
            labors.append(Double(vote.labor))
            minutes.append(Double(vote.minutes))
        }

        return ChoreValues(
            difficulty: difficulties.average,
            labor: labors.average,
            minutes: minutes.average
        )
    }

    /// The proposer's numbers on their own, before the household weighed in.
    var proposedValues: ChoreValues {
        ChoreValues(
            difficulty: Double(proposedDifficulty),
            labor: Double(proposedLabor),
            minutes: Double(proposedMinutes)
        )
    }

    /// What this chore is worth right now.
    var points: Int { PointsEngine.points(for: agreedValues) }

    /// What it was worth before peers re-rated it.
    var proposedPoints: Int { PointsEngine.points(for: proposedValues) }

    /// Point movement caused by peer ratings, e.g. +3 or -2.
    var pointDrift: Int { points - proposedPoints }

    /// Ratings stay hidden until enough are in that no single rater can be
    /// identified by elimination.
    func valuesAreRevealed(in household: Household?) -> Bool {
        votes.count >= (household?.minimumRatingsToReveal ?? 2)
    }

    /// Has this roommate already had their say on what the chore is worth?
    func hasVoted(_ roommate: Roommate) -> Bool {
        let token = AnonymityService.token(for: roommate.id, salt: anonymitySalt)
        return votes.contains { $0.raterToken == token }
    }


    /// Expected point cost this chore adds to a cycle, accounting for repeats.
    func cycleWeight(cycleDays: Int) -> Double {
        Double(points) * recurrence.occurrences(inCycleOf: cycleDays)
    }
}

/// The three things a chore is judged on.
struct ChoreValues: Equatable {
    var difficulty: Double
    var labor: Double
    var minutes: Double
}

@Model
final class ChoreValueVote {
    var id: UUID = UUID()
    /// Salted hash of the rater's ID. Enough to stop double-voting, never shown.
    var raterToken: String = ""
    var difficulty: Int = 3
    var labor: Int = 3
    var minutes: Int = 15
    var createdAt: Date = Date()

    var chore: Chore?

    init(raterToken: String, difficulty: Int, labor: Int, minutes: Int) {
        self.id = UUID()
        self.raterToken = raterToken
        self.difficulty = difficulty
        self.labor = labor
        self.minutes = minutes
        self.createdAt = Date()
    }
}

extension Array where Element == Double {
    var average: Double {
        isEmpty ? 0 : reduce(0, +) / Double(count)
    }
}
