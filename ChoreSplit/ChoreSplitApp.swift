import SwiftUI
import SwiftData
import UserNotifications

@main
struct ChoreSplitApp: App {

    @State private var appState = AppState()
    @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate

    private let container: ModelContainer = {
        let schema = Schema([
            Household.self,
            Roommate.self,
            Chore.self,
            ChoreValueVote.self,
            Assignment.self,
            QualityRating.self
        ])
        do {
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
        } catch {
            // A store that cannot be opened is unrecoverable at launch; failing loudly in
            // development beats shipping an app that silently loses a household's history.
            fatalError("Could not open the ChoreSplit store: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .tint(Theme.indigo)
                .onAppear { notificationDelegate.appState = appState }
        }
        .modelContainer(container)
    }
}

/// Handles notifications arriving while the app is open, and taps on reminders.
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Show — and speak — reminders even when the app is in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // In the foreground the custom sound is not played, so speak the line directly.
        let body = notification.request.content.body
        if notification.request.identifier.hasPrefix("chore-") {
            VoiceReminderService.shared.speak(body, rate: VoiceSettings.rate)
            return [.banner, .list]
        }
        return [.banner, .list, .sound]
    }

    /// Tapping a reminder jumps to the chore it is about.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let raw = info["assignmentID"] as? String, let id = UUID(uuidString: raw) {
            await MainActor.run {
                appState?.selectedTab = .today
                appState?.pendingAssignmentID = id
            }
        } else if response.notification.request.identifier.hasPrefix("rate-") {
            await MainActor.run { appState?.selectedTab = .rate }
        }
    }
}
