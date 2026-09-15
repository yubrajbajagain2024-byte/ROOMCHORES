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

    /// Assignment to open on appear, from a tapped notification.
    var pendingAssignmentID: UUID?

    /// An invite code from a tapped choresplit://join link, waiting until someone is signed in.
    var pendingInviteCode: String?

    /// The on-device demo household, with no account or server. Debug builds only.
    var isDemoMode: Bool = {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("--demo")
        #else
        return false
        #endif
    }()

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.activeRoommateKey) {
            activeRoommateID = UUID(uuidString: raw)
        }
    }

    func activeRoommate(in household: Household?) -> Roommate? {
        guard let household else { return nil }
        if let activeRoommateID,
           let match = household.sortedMembers.first(where: { $0.id == activeRoommateID }) {
            return match
        }
        // In a shared group you are your account, never whoever happens to be listed first.
        return household.isShared ? nil : household.sortedMembers.first
    }
}
