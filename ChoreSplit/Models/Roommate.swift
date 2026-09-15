import Foundation
import SwiftData
import SwiftUI

@Model
final class Roommate {
    var id: UUID = UUID()
    var name: String = ""
    /// Emoji shown in avatars and the leaderboard.
    var emoji: String = "🙂"
    /// Index into `Theme.memberPalette`, so every roommate reads as a distinct colour.
    var paletteIndex: Int = 0
    var joinedAt: Date = Date()

    /// Fraction of a full share this person carries. A roommate who travels half
    /// the month can be set to 0.5 and the fairness target scales down for them,
    /// so "even" does not have to mean "identical".
    var shareWeight: Double = 1.0

    /// Points carried over when a cycle rolls, so a big debt or surplus is not
    /// simply forgiven every Monday.
    var carryOverPoints: Double = 0

    /// "owner" or "member". The owner starts the group and can change its invite code.
    var role: String = "member"

    var household: Household?

    // Nullify rather than cascade: when someone leaves a shared group, the tasks they finished
    // stay in everyone's history.
    @Relationship(deleteRule: .nullify, inverse: \Assignment.assignee)
    var assignments: [Assignment]? = []

    init(name: String, emoji: String = "🙂", paletteIndex: Int = 0, shareWeight: Double = 1.0) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.paletteIndex = paletteIndex
        self.shareWeight = shareWeight
        self.joinedAt = Date()
        self.carryOverPoints = 0
    }

    var color: Color { Theme.memberColor(paletteIndex) }

    var isOwner: Bool { role == "owner" }

    /// First name plus last initial is enough to tell two roommates apart in a tight row.
    var shortName: String {
        let parts = name.split(separator: " ")
        guard let first = parts.first else { return name }
        if parts.count > 1, let initial = parts[1].first {
            return "\(first) \(initial)."
        }
        return String(first)
    }
}
