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

    /// Schedule (or reschedule) the reminder for an assignment.
    ///
    /// When a voice reminder is on, the sentence is synthesised to an audio file first
    /// and attached as the notification's sound, so the phone speaks the reminder aloud
    /// instead of playing a default chime.
    @discardableResult
    func scheduleReminder(for assignment: Assignment, assigneeName: String) async -> Bool {
        await cancelReminder(for: assignment)

        guard let fireDate = assignment.reminderDate, fireDate > Date() else { return false }

        // Synthesising a voice clip takes real time and real memory. There is no point
        // paying for it when the system will not deliver the notification anyway — callers
        // that want to prompt for permission do so before calling this.
        let status = await authorizationStatus()
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return false
        }

        let identifier = "chore-\(assignment.id.uuidString)"
        let spoken = assignment.reminderSpokenText.isEmpty
            ? ReminderPhrase.sentence(for: assignment, assigneeName: assigneeName)
            : assignment.reminderSpokenText

        let content = UNMutableNotificationContent()
        content.title = assignment.title
        content.body = spoken
        content.userInfo = ["assignmentID": assignment.id.uuidString]
        content.interruptionLevel = .timeSensitive
        content.threadIdentifier = "choresplit-reminders"

        if assignment.voiceReminderEnabled,
           let filename = await VoiceReminderService.shared.renderSoundFile(
               for: spoken,
               identifier: assignment.id.uuidString,
               rate: VoiceSettings.rate
           ) {
            content.sound = UNNotificationSound(named: UNNotificationSoundName(filename))
        } else {
            content.sound = .default
        }

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        do {
            try await center.add(request)
            assignment.notificationID = identifier
            return true
        } catch {
            return false
        }
    }

    func cancelReminder(for assignment: Assignment) async {
        let identifier = assignment.notificationID ?? "chore-\(assignment.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        VoiceReminderService.shared.deleteSoundFile(named: "reminder-\(assignment.id.uuidString).caf")
        assignment.notificationID = nil
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
        let firstName = assigneeName.split(separator: " ").first.map(String.init) ?? assigneeName
        let chore = assignment.title.lowercased()
        let points = assignment.pointsQuoted
        let pointWord = spellOut(points)
        let pointNoun = points == 1 ? "point" : "points"

        let timing: String
        let calendar = Calendar.current
        if calendar.isDateInToday(assignment.dueDate) {
            timing = "is due today"
        } else if calendar.isDateInTomorrow(assignment.dueDate) {
            timing = "is due tomorrow"
        } else if assignment.dueDate < Date() {
            timing = "is overdue"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE"
            timing = "is due on \(formatter.string(from: assignment.dueDate))"
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
