import Foundation
import SwiftUI
import SwiftData

/// Who is holding the phone.
///
/// ChoreSplit runs a whole household on one device — you hand the phone over, or leave
/// it on the kitchen counter. Everything anonymous depends on this being right, so the
/// active roommate is switched explicitly rather than guessed.
@Observable
final class AppState {
    private static let activeRoommateKey = "active.roommate.id"

    var activeRoommateID: UUID? {
        didSet {
            UserDefaults.standard.set(activeRoommateID?.uuidString, forKey: Self.activeRoommateKey)
        }
    }

    /// Set when the app wants to pull the user to a particular tab, e.g. after tapping
    /// a reminder notification.
    var selectedTab: AppTab = .today

    /// Assignment to open on appear, from a tapped notification.
    var pendingAssignmentID: UUID?

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.activeRoommateKey) {
            activeRoommateID = UUID(uuidString: raw)
        }
        #if DEBUG
        // `--tab chores` etc. opens straight onto a tab, for driving the app in a simulator.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--tab"), index + 1 < arguments.count {
            switch arguments[index + 1] {
            case "chores":    selectedTab = .chores
            case "rate":      selectedTab = .rate
            case "standings": selectedTab = .standings
            case "settings":  selectedTab = .settings
            default:          selectedTab = .today
            }
        }
        #endif
    }

    func activeRoommate(in household: Household?) -> Roommate? {
        guard let household else { return nil }
        if let activeRoommateID,
           let match = household.sortedMembers.first(where: { $0.id == activeRoommateID }) {
            return match
        }
        return household.sortedMembers.first
    }
}

enum AppTab: Hashable {
    case today, chores, rate, standings, settings
}
