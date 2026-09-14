import Foundation
import SwiftUI

// MARK: - Chore category

enum ChoreCategory: String, Codable, CaseIterable, Identifiable {
    case kitchen, bathroom, living, laundry, trash, outdoor, admin, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .kitchen:  return "Kitchen"
        case .bathroom: return "Bathroom"
        case .living:   return "Living areas"
        case .laundry:  return "Laundry"
        case .trash:    return "Trash & recycling"
        case .outdoor:  return "Outdoor"
        case .admin:    return "Household admin"
        case .other:    return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .kitchen:  return "fork.knife"
        case .bathroom: return "shower.fill"
        case .living:   return "sofa.fill"
        case .laundry:  return "washer.fill"
        case .trash:    return "trash.fill"
        case .outdoor:  return "leaf.fill"
        case .admin:    return "doc.text.fill"
        case .other:    return "square.grid.2x2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .kitchen:  return Theme.amber
        case .bathroom: return Theme.teal
        case .living:   return Theme.indigo
        case .laundry:  return Theme.sky
        case .trash:    return Theme.slate
        case .outdoor:  return Theme.green
        case .admin:    return Theme.violet
        case .other:    return Theme.slate
        }
    }
}

// MARK: - Recurrence

/// How often a chore comes back around. Drives assignment generation each cycle.
enum Recurrence: String, Codable, CaseIterable, Identifiable {
    case once, daily, everyOtherDay, weekly, biweekly, monthly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .once:          return "One time"
        case .daily:         return "Every day"
        case .everyOtherDay: return "Every other day"
        case .weekly:        return "Every week"
        case .biweekly:      return "Every 2 weeks"
        case .monthly:       return "Every month"
        }
    }

    /// Days between occurrences. `nil` for one-off chores.
    var intervalDays: Int? {
        switch self {
        case .once:          return nil
        case .daily:         return 1
        case .everyOtherDay: return 2
        case .weekly:        return 7
        case .biweekly:      return 14
        case .monthly:       return 30
        }
    }

    /// Roughly how many times this chore lands inside a cycle of `cycleDays`.
    /// Used to work out each roommate's fair share of points for the cycle.
    func occurrences(inCycleOf cycleDays: Int) -> Double {
        guard let interval = intervalDays else { return 1 }
        return max(1, Double(cycleDays) / Double(interval))
    }
}

// MARK: - Assignment lifecycle

enum AssignmentStatus: String, Codable, CaseIterable {
    /// Assigned, not yet done.
    case open
    /// Marked done by the assignee, waiting on peer quality ratings.
    case awaitingReview
    /// Ratings closed (or skipped); points are final and banked.
    case settled
    /// Nobody did it before the due date passed and it was written off.
    case skipped

    var label: String {
        switch self {
        case .open:           return "To do"
        case .awaitingReview: return "Being rated"
        case .settled:        return "Done"
        case .skipped:        return "Skipped"
        }
    }

    var symbol: String {
        switch self {
        case .open:           return "circle"
        case .awaitingReview: return "hourglass"
        case .settled:        return "checkmark.circle.fill"
        case .skipped:        return "xmark.circle"
        }
    }
}

// MARK: - Onboarding stage

/// The household walks through setup together before day-to-day use begins.
enum SetupStage: String, Codable {
    /// Name the household, set the cycle length.
    case household
    /// Add every roommate.
    case roommates
    /// Everyone adds the chores they think need doing, with proposed point values.
    case choreBuilding
    /// Setup finished; the app is in normal use.
    case running
}
