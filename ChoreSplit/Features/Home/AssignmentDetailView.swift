import SwiftUI
import SwiftData
import AVFoundation

struct AssignmentDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @Bindable var assignment: Assignment
    let household: Household

    @State private var reminderOn = false
    @State private var reminderDate = Date()
    @State private var spokenText = ""
    @State private var isEditingPhrase = false
    @State private var notificationsDenied = false
    @State private var showingFinish = false

    private var me: Roommate? { appState.activeRoommate(in: household) }
    private var isMine: Bool { assignment.assignee?.id == me?.id }
    private var chore: Chore? { assignment.chore }

    var body: some View {
        NavigationStack {
            Form {
                overviewSection

                if assignment.status == .open {
                    voiceReminderSection
                }

                if let chore {
                    valueSection(chore: chore)
                }

                switch assignment.status {
                case .awaitingReview: ratingProgressSection
                case .settled:        settledSection
                default:              EmptyView()
                }

                if assignment.status == .open, isMine {
                    actionSection
                }
            }
            .navigationTitle(assignment.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: load)
            .sheet(isPresented: $showingFinish) {
                CompleteTaskSheet(assignment: assignment, household: household) { dismiss() }
            }
            .onDisappear { VoiceReminderService.shared.stopSpeaking() }
            .alert("Notifications are off", isPresented: $notificationsDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("ChoreSplit needs notification permission to speak reminders when the app isn't open.")
            }
        }
    }

    // MARK: - Overview

    private var overviewSection: some View {
        Section {
            HStack(spacing: 12) {
                if let assignee = assignment.assignee {
                    AvatarView(roommate: assignee, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(assignee.name).font(.headline)
                        Text(assignment.status.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                PointsBadge(
                    points: assignment.effectivePoints,
                    provisional: assignment.pointsAreProvisional,
                    size: .large
                )
            }
            .padding(.vertical, 4)

            LabeledContent("Due") {
                Text(dueText)
                    .foregroundStyle(assignment.isOverdue ? Theme.rose : .primary)
            }

            if let chore, !chore.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    Text(chore.notes).font(.subheadline)
                }
                .padding(.vertical, 2)
            }

            if assignment.wasAutoAssigned, !assignment.assignmentReason.isEmpty {
                Label(assignment.assignmentReason, systemImage: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(Theme.amber)
            }
        }
    }

    private var dueText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: assignment.dueDate)
    }

    // MARK: - Voice reminder

    private var voiceReminderSection: some View {
        Section {
            Toggle(isOn: $reminderOn) {
                Label("Remind me", systemImage: "bell.badge")
            }
            .onChange(of: reminderOn) { _, _ in saveReminder() }

            if reminderOn {
                DatePicker(
                    "When",
                    selection: $reminderDate,
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .onChange(of: reminderDate) { _, _ in saveReminder() }

                Toggle(isOn: $assignment.voiceReminderEnabled) {
                    Label("Say it out loud", systemImage: "waveform")
                }
                .onChange(of: assignment.voiceReminderEnabled) { _, _ in saveReminder() }

                if assignment.voiceReminderEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("What it will say")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if isEditingPhrase {
                            TextField("Reminder", text: $spokenText, axis: .vertical)
                                .lineLimit(2...4)
                                .onSubmit { saveReminder() }
                        } else {
                            Text("\u{201C}\(spokenText)\u{201D}")
                                .font(.subheadline)
                                .italic()
                        }

                        HStack(spacing: 10) {
                            Button {
                                VoiceReminderService.shared.speak(spokenText, rate: VoiceSettings.rate)
                            } label: {
                                Label("Preview", systemImage: "play.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                isEditingPhrase.toggle()
                                if !isEditingPhrase { saveReminder() }
                            } label: {
                                Label(isEditingPhrase ? "Save wording" : "Edit wording",
                                      systemImage: isEditingPhrase ? "checkmark" : "pencil")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button {
                                spokenText = ReminderPhrase.sentence(
                                    for: assignment,
                                    assigneeName: assignment.assignee?.name ?? ""
                                )
                                saveReminder()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityLabel("Reset wording")
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Reminder")
        } footer: {
            Text(assignment.voiceReminderEnabled && reminderOn
                 ? "The sentence is recorded now and played as the notification sound, so your phone speaks it even if ChoreSplit isn't open."
                 : "A standard notification with no voice.")
        }
    }

    // MARK: - What it's worth

    private func valueSection(chore: Chore) -> some View {
        Section {
            PointsPreview(values: chore.agreedValues, points: chore.points)
        } header: {
            Text("What this task is worth")
        }
    }

    // MARK: - Ratings

    private var ratingProgressSection: some View {
        let raters = assignment.eligibleRaters(in: household)
        let rated = assignment.ratingCount

        return Section {
            HStack {
                Text("Ratings in")
                Spacer()
                Text("\(rated) of \(raters.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let deadline = assignment.ratingDeadline(in: household) {
                LabeledContent("Points settle") {
                    Text(deadline, style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            if let average = assignment.revealedAverage(in: household) {
                LabeledContent("How it went") {
                    Text(PointsEngine.describeQuality(average))
                        .foregroundStyle(Theme.qualityColor(average))
                }
                anonymousNotes
            } else {
                Label(
                    "Scores stay hidden until \(household.minimumRatingsToReveal) are in, so a single rating can't be traced back to one person.",
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Peer review")
        }
    }

    private var settledSection: some View {
        Section {
            LabeledContent("Points banked") {
                Text(PointsEngine.format(assignment.awardedPoints ?? Double(assignment.pointsQuoted)))
                    .fontWeight(.semibold)
            }
            LabeledContent("Chore worth") {
                Text("\(assignment.pointsQuoted) of \(PointsEngine.maximumPoints) pts").foregroundStyle(.secondary)
            }

            if let average = assignment.revealedAverage(in: household) {
                LabeledContent("Peer verdict") {
                    Text("\(PointsEngine.describeQuality(average)) · \(String(format: "%.1f", average))/5")
                        .foregroundStyle(Theme.qualityColor(average))
                }
                anonymousNotes
            } else if assignment.ratingCount == 0 {
                Label("Nobody rated this, so it paid full points.", systemImage: "equal.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    "Only \(assignment.ratingCount) rating came in — too few to show without giving away who wrote it.",
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Result")
        }
    }

    @ViewBuilder
    private var anonymousNotes: some View {
        let notes = assignment.revealedNotes(in: household)
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Anonymous notes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                    Text("\u{201C}\(note)\u{201D}")
                        .font(.subheadline)
                        .italic()
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(.tertiarySystemFill))
                        )
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Actions

    private var actionSection: some View {
        Section {
            Button {
                showingFinish = true
            } label: {
                Label("Finish with a video", systemImage: "video.badge.checkmark")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Button(role: .destructive) {
                HouseholdActions.markSkipped(assignment, context: context)
                dismiss()
            } label: {
                Label("Skip — I'm not doing this one", systemImage: "xmark.circle")
            }
        }
    }

    // MARK: - Reminder plumbing

    private func load() {
        reminderOn = assignment.reminderDate != nil
        reminderDate = assignment.reminderDate
            ?? HouseholdActions.defaultReminderDate(for: assignment.dueDate)
            ?? Date().addingTimeInterval(3600)
        spokenText = assignment.reminderSpokenText.isEmpty
            ? ReminderPhrase.sentence(for: assignment, assigneeName: assignment.assignee?.name ?? "")
            : assignment.reminderSpokenText
    }

    private func saveReminder() {
        assignment.reminderSpokenText = spokenText
        assignment.reminderDate = reminderOn ? reminderDate : nil
        try? context.save()

        let reminder = NotificationService.ReminderRequest(
            assignment: assignment,
            assigneeName: assignment.assignee?.name ?? ""
        )
        let isOn = reminderOn
        Task {
            if isOn {
                let outcome = await NotificationService.shared.scheduleReminderRequestingPermission(reminder)
                if outcome == .permissionDenied {
                    await MainActor.run { notificationsDenied = true }
                }
            } else {
                await NotificationService.shared.cancelReminder(assignmentID: reminder.assignmentID)
            }
        }
    }
}
