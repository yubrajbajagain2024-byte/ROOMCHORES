import Foundation
import UserNotifications

/// Schedules chore reminders, with the rendered voice clip as the notification sound.
final class NotificationService {

    static let shared = NotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    // MARK: - Scheduling

    /// Everything a reminder needs, copied out of the assignment up front.
    ///
    /// Scheduling hops off the main thread to record the voice clip and talk to the
    /// notification centre. SwiftData objects belong to the thread that owns their context, so
    /// the work carries plain values rather than the assignment itself — touching the model
    /// from a background task is a data race that can crash the app.
    struct ReminderRequest: Sendable {
        let assignmentID: UUID
        let title: String
        let spokenText: String
        let fireDate: Date?
        let voiceEnabled: Bool

        init(assignment: Assignment, assigneeName: String) {
            assignmentID = assignment.id
            title = assignment.title
            spokenText = assignment.reminderSpokenText.isEmpty
                ? ReminderPhrase.sentence(for: assignment, assigneeName: assigneeName)
                : assignment.reminderSpokenText
            fireDate = assignment.reminderDate
            voiceEnabled = assignment.voiceReminderEnabled
        }
    }

    static func identifier(for assignmentID: UUID) -> String {
        "chore-\(assignmentID.uuidString)"
    }

    /// Schedule (or reschedule) a reminder.
    ///
    /// When a voice reminder is on, the sentence is synthesised to an audio file first and
    /// attached as the notification's sound, so the phone speaks the reminder aloud instead of
    /// playing a default chime.
    @discardableResult
    func scheduleReminder(_ reminder: ReminderRequest) async -> Bool {
        await cancelReminder(assignmentID: reminder.assignmentID)

        guard let fireDate = reminder.fireDate, fireDate > Date() else { return false }

        // Synthesising a voice clip takes real time and real memory. There is no point
        // paying for it when the system will not deliver the notification anyway — callers
        // that want to prompt for permission do so before calling this.
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return false
        }

        let content = UNMutableNotificationContent()
        content.title = reminder.title
        content.body = reminder.spokenText
        content.userInfo = ["assignmentID": reminder.assignmentID.uuidString]
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "choresplit-reminders"

        if reminder.voiceEnabled,
           let filename = await VoiceReminderService.shared.renderSoundFile(
               for: reminder.spokenText,
               identifier: reminder.assignmentID.uuidString,
               rate: VoiceSettings.rate
           ) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(filename))
        } else {
            content.sound = .default
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let request = UNNotificationRequest(
            identifier: Self.identifier(for: reminder.assignmentID),
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        do {
            try await center.add(request)
            return true
        } catch {
            return false
        }
    }

    enum ReminderOutcome {
        case scheduled
        /// Notifications are switched off for the app; the UI should say so.
        case permissionDenied
        /// Nothing to schedule — no date, or the date has already passed.
        case notScheduled
    }

    /// Schedule a reminder the user has just set, asking for notification permission first
    /// if the app has never asked.
    func scheduleReminderRequestingPermission(_ reminder: ReminderRequest) async -> ReminderOutcome {
        switch await authorizationStatus() {
        case .denied:
            return .permissionDenied
        case .notDetermined:
            guard await requestAuthorization() else { return .permissionDenied }
        default:
            break
        }
        return await scheduleReminder(reminder) ? .scheduled : .notScheduled
    }

    func cancelReminder(assignmentID: UUID) async {
        center.removePendingNotificationRequests(withIdentifiers: [Self.identifier(for: assignmentID)])
        VoiceReminderService.shared.deleteSoundFile(named: "reminder-\(assignmentID.uuidString).caf")
    }

    /// Nudge the household when someone's completed chore is waiting on peer ratings.
    func scheduleRatingNudge(assignmentTitle: String, at date: Date, assignmentID: UUID) async {
        guard date > Date() else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rate a chore"
        content.body = "\"\(assignmentTitle)\" is waiting on your anonymous rating."
        content.sound = .default
        content.threadIdentifier = "choresplit-ratings"

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(
            identifier: "rate-\(assignmentID.uuidString)",
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
        try? await center.add(request)
    }
    /// Clear scheduled reminders and their audio for assignments that no longer exist.
    func pruneOrphans(activeAssignmentIDs: Set<UUID>) async {
        let requests = await center.pendingNotificationRequests()
        var stale: [String] = []
        for request in requests where request.identifier.hasPrefix("chore-") {
            let raw = String(request.identifier.dropFirst("chore-".count))
            if let uuid = UUID(uuidString: raw), !activeAssignmentIDs.contains(uuid) {
                stale.append(request.identifier)
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        let keep = Set(activeAssignmentIDs.map { "reminder-\($0.uuidString).caf" })
        VoiceReminderService.shared.pruneSoundFiles(keeping: keep)
    }
}

/// Builds the sentence the phone actually says.
///
/// Written for the ear rather than the eye: numbers are spelled out, the person is named
/// first so they know it is for them, and the point value goes last because that is the
/// part that makes anyone get off the sofa.
enum ReminderPhrase {

    static func sentence(for assignment: Assignment, assigneeName: String) -> String {
        sentence(
            assigneeName: assigneeName,
            choreTitle: assignment.title,
            points: assignment.pointsQuoted,
            dueDate: assignment.dueDate
        )
    }

    /// The same sentence before an assignment exists — used to preview a reminder while a
    /// task is still being set up.
    static func sentence(assigneeName: String, choreTitle: String, points: Int, dueDate: Date) -> String {
        let firstName = assigneeName.split(separator: " ").first.map(String.init) ?? assigneeName
        let chore = choreTitle.lowercased()
        let pointWord = spellOut(points)
        let pointNoun = points == 1 ? "point" : "points"

        let timing: String
        let calendar = Calendar.current
        if calendar.isDateInToday(dueDate) {
            timing = "is due today"
        } else if calendar.isDateInTomorrow(dueDate) {
            timing = "is due tomorrow"
        } else if dueDate < Date() {
            timing = "is overdue"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            timing = "is due on \(formatter.string(from: dueDate))"
        }

        return "\(firstName), \(chore) \(timing). That's \(pointWord) \(pointNoun)."
    }

    /// Text-to-speech reads "4" fine, but spelled-out numbers land more naturally in a
    /// full sentence and avoid it being read as a date or a time.
    static func spellOut(_ number: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .spellOut
        return formatter.string(from: NSNumber(value: number)) ?? "\(number)"
    }
}
