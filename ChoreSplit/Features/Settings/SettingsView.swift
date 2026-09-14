import SwiftUI
import SwiftData
import AVFoundation
import UserNotifications

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var household: Household

    @State private var showingSwitcher = false
    @State private var showingResetConfirm = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    private var me: Roommate? { appState.activeRoommate(in: household) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Household name", text: $household.name)

                    Picker("Cycle length", selection: $household.cycleLengthDays) {
                        Text("3 days").tag(3)
                        Text("A week").tag(7)
                        Text("A fortnight").tag(14)
                    }
                } header: {
                    Text("Household")
                } footer: {
                    Text("Fair shares are judged inside one cycle, so a busy week doesn't follow you around forever.")
                }

                Section {
                    Toggle("Hand out catch-up chores automatically", isOn: $household.autoAssignEnabled)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("How far behind before it steps in")
                            Spacer()
                            Text("\(Int(household.fairnessTolerance * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $household.fairnessTolerance, in: 0.05...0.35, step: 0.05)
                    }
                } header: {
                    Text("Balancing")
                } footer: {
                    Text(household.autoAssignEnabled
                         ? "Anyone more than \(Int(household.fairnessTolerance * 100))% below their share gets extra chores when the app next opens."
                         : "Off — nobody gets extra chores unless you tap \u{201C}Even it out\u{201D} on the Standings tab.")
                }

                Section {
                    Stepper(value: $household.minimumRatingsToReveal, in: 1...max(1, household.sortedMembers.count)) {
                        HStack {
                            Text("Hide scores until")
                            Spacer()
                            Text("\(household.minimumRatingsToReveal) rating\(household.minimumRatingsToReveal == 1 ? "" : "s")")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Picker("Rating window", selection: $household.ratingWindowHours) {
                        Text("12 hours").tag(12)
                        Text("A day").tag(24)
                        Text("2 days").tag(48)
                        Text("3 days").tag(72)
                    }
                } header: {
                    Text("Anonymous ratings")
                } footer: {
                    Text("A threshold of 1 means a lone rating is shown immediately — in a small flat that's usually enough to work out who left it. Two is the safe default. Anything still unrated when the window closes pays the chore's face value.")
                }

                VoiceSettingsSection()

                Section {
                    switch notificationStatus {
                    case .authorized, .provisional, .ephemeral:
                        Label("Reminders are allowed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                    case .denied:
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            Label("Notifications are off — open Settings", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.amber)
                        }
                    default:
                        Button("Allow reminders") {
                            Task {
                                await NotificationService.shared.requestAuthorization()
                                notificationStatus = await NotificationService.shared.authorizationStatus()
                            }
                        }
                    }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Voice reminders are played as the notification sound, so they need notification permission to speak while the app is closed.")
                }

                Section {
                    ForEach(household.sortedMembers) { member in
                        NavigationLink {
                            RoommateSettingsView(member: member, household: household)
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(roommate: member, size: 34)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(member.name)
                                    Text(member.shareWeight == 1.0
                                         ? "Full share"
                                         : "\(Int(member.shareWeight * 100))% share")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if member.id == me?.id {
                                    Text("you")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Roommates")
                }

                Section {
                    Button("Start a new cycle now") {
                        FairnessEngine.rollCycle(for: household)
                        try? context.save()
                    }

                    Button("Reset everything", role: .destructive) {
                        showingResetConfirm = true
                    }
                } header: {
                    Text("Household admin")
                } footer: {
                    Text("Starting a new cycle banks the current scores and carries half of any imbalance forward.")
                }

                Section {
                    LabeledContent("Version", value: "1.0")
                } footer: {
                    Text("ChoreSplit keeps everything on this device. Nothing is uploaded, and no account is needed.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ActiveUserButton(household: household, showingSwitcher: $showingSwitcher, activeMember: me)
            }
            .sheet(isPresented: $showingSwitcher) {
                UserSwitcherSheet(household: household)
                    .presentationDetents([.medium])
            }
            .confirmationDialog(
                "Reset the whole household?",
                isPresented: $showingResetConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete everything", role: .destructive, action: resetAll)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This deletes every roommate, chore, assignment and rating, and starts setup again. It can't be undone.")
            }
            .task {
                notificationStatus = await NotificationService.shared.authorizationStatus()
            }
            .onChange(of: household.cycleLengthDays) { _, _ in try? context.save() }
            .onChange(of: household.fairnessTolerance) { _, _ in try? context.save() }
            .onChange(of: household.minimumRatingsToReveal) { _, _ in try? context.save() }
            .onChange(of: household.ratingWindowHours) { _, _ in try? context.save() }
            .onChange(of: household.autoAssignEnabled) { _, _ in try? context.save() }
        }
    }

    private func resetAll() {
        for assignment in household.assignments ?? [] { context.delete(assignment) }
        for chore in household.chores ?? [] { context.delete(chore) }
        for member in household.members ?? [] { context.delete(member) }
        appState.activeRoommateID = nil
        household.setupStage = .household
        household.cycleStartDate = Calendar.current.startOfDay(for: Date())
        try? context.save()

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        VoiceReminderService.shared.pruneSoundFiles(keeping: [])
    }
}

// MARK: - Voice

struct VoiceSettingsSection: View {
    @State private var voiceIdentifier = VoiceSettings.selectedVoiceIdentifier
    @State private var rate = VoiceSettings.rate

    private let sampleText = "Alex, the kitchen bins are due tonight. That's four points."

    var body: some View {
        Section {
            Picker("Voice", selection: $voiceIdentifier) {
                Text("System default").tag(String?.none)
                ForEach(VoiceReminderService.availableVoices, id: \.identifier) { voice in
                    Text(displayName(for: voice)).tag(String?.some(voice.identifier))
                }
            }
            .onChange(of: voiceIdentifier) { _, newValue in
                VoiceSettings.selectedVoiceIdentifier = newValue
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Speed")
                    Spacer()
                    Text(speedLabel).foregroundStyle(.secondary)
                }
                Slider(
                    value: $rate,
                    in: AVSpeechUtteranceMinimumSpeechRate...AVSpeechUtteranceMaximumSpeechRate
                )
                .onChange(of: rate) { _, newValue in
                    VoiceSettings.rate = newValue
                }
            }

            Button {
                VoiceReminderService.shared.speak(sampleText, rate: rate)
            } label: {
                Label("Hear a sample", systemImage: "play.circle.fill")
            }
        } header: {
            Text("Voice reminders")
        } footer: {
            Text("More natural voices can be downloaded in iOS Settings under Accessibility \u{203A} Spoken Content \u{203A} Voices.")
        }
    }

    private var speedLabel: String {
        let range = AVSpeechUtteranceMaximumSpeechRate - AVSpeechUtteranceMinimumSpeechRate
        let fraction = (rate - AVSpeechUtteranceMinimumSpeechRate) / range
        switch fraction {
        case ..<0.3:  return "Slow"
        case ..<0.55: return "Normal"
        case ..<0.75: return "Brisk"
        default:      return "Fast"
        }
    }

    private func displayName(for voice: AVSpeechSynthesisVoice) -> String {
        let quality: String
        switch voice.quality {
        case .premium:  quality = " (premium)"
        case .enhanced: quality = " (enhanced)"
        default:        quality = ""
        }
        return "\(voice.name)\(quality)"
    }
}

// MARK: - Per-roommate settings

struct RoommateSettingsView: View {
    @Environment(\.modelContext) private var context
    @Bindable var member: Roommate
    let household: Household

    @State private var showingEmojiPicker = false

    private var standing: MemberStanding? {
        FairnessEngine.standings(for: household).first { $0.roommate.id == member.id }
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Button { showingEmojiPicker = true } label: {
                        AvatarView(roommate: member, size: 56)
                    }
                    .buttonStyle(.plain)
                    TextField("Name", text: $member.name)
                        .font(.title3)
                }
                .padding(.vertical, 4)

                Picker("Colour", selection: $member.paletteIndex) {
                    ForEach(0..<Theme.memberPalette.count, id: \.self) { index in
                        HStack {
                            Circle().fill(Theme.memberColor(index)).frame(width: 16, height: 16)
                            Text("Colour \(index + 1)")
                        }
                        .tag(index)
                    }
                }
            }

            Section {
                Picker("Share of the chores", selection: $member.shareWeight) {
                    Text("Full share").tag(1.0)
                    Text("Three quarters").tag(0.75)
                    Text("Half share").tag(0.5)
                    Text("Quarter share").tag(0.25)
                }
            } footer: {
                Text("Use a reduced share for someone who's away a lot. Their fair-share target scales down to match, so \u{201C}even\u{201D} doesn't have to mean \u{201C}identical\u{201D}.")
            }

            if let standing {
                Section {
                    LabeledContent("Carrying") {
                        Text("\(Int(standing.load.rounded())) of \(Int(standing.target.rounded())) pts")
                    }
                    LabeledContent("Carry-over") {
                        Text(member.carryOverPoints == 0
                             ? "None"
                             : member.carryOverPoints > 0
                               ? "Owes \(Int(member.carryOverPoints)) pts"
                               : "Credit of \(Int(-member.carryOverPoints)) pts")
                            .foregroundStyle(.secondary)
                    }
                    if member.carryOverPoints != 0 {
                        Button("Clear carry-over") {
                            member.carryOverPoints = 0
                            try? context.save()
                        }
                    }
                } header: {
                    Text("This cycle")
                }
            }
        }
        .navigationTitle(member.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerView(selection: $member.emoji)
                .presentationDetents([.medium])
        }
        .onDisappear { try? context.save() }
    }
}
