import SwiftUI
import SwiftData

/// Add something to do straight from the home page: take a chore from the household's list
/// or write a new one, decide who it's for and when it's due, and set the reminder — all in
/// one place, so nobody has to add a task and then go hunting for where reminders live.
struct AddTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let household: Household
    /// Whoever is holding the phone. New tasks default to them.
    let creator: Roommate

    private enum Source: String, CaseIterable, Identifiable {
        case list = "From chore list"
        case new = "New task"
        var id: String { rawValue }
    }

    private enum AssigneeChoice: Hashable {
        case member(UUID)
        /// Resolved at save time, so it picks whoever is behind at that moment.
        case furthestBehind
    }

    @State private var source: Source
    @State private var selectedChoreID: UUID?

    // New task
    @State private var title = ""
    @State private var notes = ""
    @State private var category: ChoreCategory = .other
    @State private var recurrence: Recurrence = .once
    @State private var difficulty = 2
    @State private var labor = 2
    @State private var minutes = 15

    // Who and when
    @State private var assigneeChoice: AssigneeChoice
    @State private var dueDate: Date

    // Reminder
    @State private var reminderOn = true
    @State private var reminderDate: Date
    /// Once the user picks a reminder time by hand, changing the due date stops moving it.
    @State private var reminderTimeChosen = false
    @State private var voiceOn = true
    /// `nil` means "use the generated sentence", which follows the task as it's edited.
    @State private var customWording: String?
    @State private var isEditingWording = false
    @State private var wordingDraft = ""

    @State private var permissionDenied = false
    @FocusState private var titleFocused: Bool

    init(household: Household, creator: Roommate) {
        self.household = household
        self.creator = creator
        let due = Self.defaultDueDate()
        _dueDate = State(initialValue: due)
        _reminderDate = State(initialValue: Self.suggestedReminder(forDue: due))
        _assigneeChoice = State(initialValue: .member(creator.id))
        // With nothing left on the list, start on the tab that can actually add something.
        _source = State(initialValue: FairnessEngine.availableChores(in: household).isEmpty ? .new : .list)
    }

    // MARK: - Derived

    private var availableChores: [Chore] {
        FairnessEngine.availableChores(in: household)
            .sorted { ($0.category.label, $0.title) < ($1.category.label, $1.title) }
    }

    private var selectedChore: Chore? {
        availableChores.first { $0.id == selectedChoreID }
    }

    private var newValues: ChoreValues {
        ChoreValues(difficulty: Double(difficulty), labor: Double(labor), minutes: Double(minutes))
    }

    private var taskTitle: String {
        switch source {
        case .list: return selectedChore?.title ?? ""
        case .new:  return title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private var taskPoints: Int {
        switch source {
        case .list: return selectedChore?.points ?? PointsEngine.minimumPoints
        case .new:  return PointsEngine.points(for: newValues)
        }
    }

    private var resolvedAssignee: Roommate? {
        switch assigneeChoice {
        case .member(let id):  return household.sortedMembers.first { $0.id == id }
        case .furthestBehind:  return FairnessEngine.nextInLine(for: household) ?? creator
        }
    }

    private var generatedWording: String {
        ReminderPhrase.sentence(
            assigneeName: resolvedAssignee?.name ?? creator.name,
            choreTitle: taskTitle,
            points: taskPoints,
            dueDate: dueDate
        )
    }

    private var wording: String { customWording ?? generatedWording }

    /// False when giving a task to someone else in a shared group: their phone reminds them.
    private var remindsOnThisPhone: Bool {
        guard let assignee = resolvedAssignee else { return true }
        return HouseholdActions.remindsOnThisPhone(for: assignee, in: household)
    }

    private var canSave: Bool {
        guard resolvedAssignee != nil, !taskTitle.isEmpty else { return false }
        return !(reminderOn && remindsOnThisPhone) || reminderDate > Date()
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Task source", selection: $source) {
                        ForEach(Source.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                switch source {
                case .list: listSection
                case .new:  newTaskSections
                }

                whoAndWhenSection
                reminderSection
            }
            .navigationTitle("Add a task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: save)
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                }
            }
            .onChange(of: dueDate) { _, newDue in
                guard !reminderTimeChosen else { return }
                reminderDate = Self.suggestedReminder(forDue: newDue)
            }
            .onChange(of: source) { _, newSource in
                if newSource == .new, title.isEmpty { titleFocused = true }
            }
            .onDisappear { VoiceReminderService.shared.stopSpeaking() }
            .alert("Task added — but reminders are off", isPresented: $permissionDenied) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                    dismiss()
                }
                Button("OK", role: .cancel) { dismiss() }
            } message: {
                Text("ChoreSplit can't remind anyone until notifications are turned on for it in Settings.")
            }
        }
    }

    // MARK: - From the list

    @ViewBuilder
    private var listSection: some View {
        if availableChores.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Everything on the chore list is already on someone's to-do list.")
                        .font(.subheadline)
                    Button("Write a new task instead") { source = .new }
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 4)
            }
        } else {
            Section {
                Picker("Chore", selection: $selectedChoreID) {
                    Text("Choose a chore").tag(UUID?.none)
                    ForEach(availableChores) { chore in
                        HStack {
                            Label(chore.title, systemImage: chore.category.symbol)
                            Spacer()
                            Text("\(chore.points) pts")
                                .foregroundStyle(.secondary)
                        }
                        .tag(UUID?.some(chore.id))
                    }
                }
                .pickerStyle(.navigationLink)

                if let chore = selectedChore {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            CategoryChip(category: chore.category)
                            Text("\(chore.recurrence.label) · about \(chore.proposedMinutes) min")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 6) {
                            PointsBadge(points: Double(chore.points), tint: chore.category.tint)
                            PointsScale(points: chore.points, tint: chore.category.tint, pipSize: 7)
                        }
                    }
                    .padding(.vertical, 4)

                    if !chore.notes.isEmpty {
                        Text(chore.notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Task")
            } footer: {
                Text("Only chores that aren't already on someone's list are shown.")
            }
        }
    }

    // MARK: - New task

    @ViewBuilder
    private var newTaskSections: some View {
        Section {
            TextField("What needs doing?", text: $title)
                .focused($titleFocused)
            TextField("Notes (optional)", text: $notes, axis: .vertical)
                .lineLimit(1...3)
            Picker("Area", selection: $category) {
                ForEach(ChoreCategory.allCases) { option in
                    Label(option.label, systemImage: option.symbol).tag(option)
                }
            }
            Picker("Repeats", selection: $recurrence) {
                ForEach(Recurrence.allCases) { Text($0.label).tag($0) }
            }
        } header: {
            Text("Task")
        } footer: {
            Text(recurrence == .once
                 ? "A one-time task is gone once it's done."
                 : "A repeating task comes back after it's done, and the next turn goes to whoever has the fewest points.")
        }

        Section {
            ScaleSlider(
                title: "Difficulty",
                lowLabel: "Mindless",
                highLabel: "Fiddly or grim",
                symbol: "brain.head.profile",
                tint: Theme.violet,
                value: $difficulty
            )
            .padding(.vertical, 4)

            ScaleSlider(
                title: "Physical effort",
                lowLabel: "Barely move",
                highLabel: "Hauling and scrubbing",
                symbol: "figure.strengthtraining.functional",
                tint: Theme.teal,
                value: $labor
            )
            .padding(.vertical, 4)

            MinutesSlider(minutes: $minutes)
                .padding(.vertical, 4)

            PointsPreview(values: newValues, points: taskPoints)
        } header: {
            Text("How big is it?")
        } footer: {
            Text("Harder, heavier and longer tasks are worth more — from 1 point up to 4. Once it's done, your roommates rate how well it went.")
        }
    }

    // MARK: - Who and when

    private var whoAndWhenSection: some View {
        Section {
            Picker("For", selection: $assigneeChoice) {
                ForEach(household.sortedMembers) { member in
                    Text(member.id == creator.id ? "Me (\(member.shortName))" : member.name)
                        .tag(AssigneeChoice.member(member.id))
                }
                if let next = FairnessEngine.nextInLine(for: household) {
                    Text("Fewest points (\(next.shortName))")
                        .tag(AssigneeChoice.furthestBehind)
                }
            }

            DatePicker("Due", selection: $dueDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
        } header: {
            Text("Who and when")
        }
    }

    // MARK: - Reminder

    @ViewBuilder
    private var reminderSection: some View {
        if remindsOnThisPhone {
            reminderControls
        } else {
            Section {
                Label("\(resolvedAssignee?.shortName ?? "They") will get a reminder on their own phone.", systemImage: "iphone.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Reminder")
            }
        }
    }

    private var reminderControls: some View {
        Section {
            Toggle(isOn: $reminderOn.animation()) {
                Label("Remind", systemImage: "bell.badge")
            }

            if reminderOn {
                DatePicker(
                    "At",
                    selection: Binding(
                        get: { reminderDate },
                        set: { reminderDate = $0; reminderTimeChosen = true }
                    ),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )

                let presets = reminderPresets
                if !presets.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(presets, id: \.label) { preset in
                                Button(preset.label) {
                                    reminderDate = preset.date
                                    reminderTimeChosen = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .tint(isSameMinute(preset.date, reminderDate) ? Theme.indigo : .secondary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }

                Toggle(isOn: $voiceOn.animation()) {
                    Label("Say it out loud", systemImage: "waveform")
                }

                if voiceOn {
                    wordingEditor
                }
            }
        } header: {
            Text("Reminder")
        } footer: {
            if reminderOn && reminderDate <= Date() {
                Text("That reminder time has already passed — pick a later one.")
                    .foregroundStyle(Theme.rose)
            } else if reminderOn && voiceOn {
                Text("The sentence is recorded when you add the task and played as the notification sound, so the phone speaks it even when ChoreSplit is closed.")
            } else if reminderOn {
                Text("A standard notification, with no voice.")
            }
        }
    }

    @ViewBuilder
    private var wordingEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What it will say")
                .font(.caption)
                .foregroundStyle(.secondary)

            if isEditingWording {
                TextField("Reminder", text: $wordingDraft, axis: .vertical)
                    .lineLimit(2...4)
            } else if taskTitle.isEmpty {
                Text(source == .list ? "Choose a chore to hear its reminder." : "Name the task to hear its reminder.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("\u{201C}\(wording)\u{201D}")
                    .font(.subheadline)
                    .italic()
            }

            HStack(spacing: 10) {
                Button {
                    VoiceReminderService.shared.speak(isEditingWording ? wordingDraft : wording, rate: VoiceSettings.rate)
                } label: {
                    Label("Preview", systemImage: "play.circle.fill")
                }
                .disabled(taskTitle.isEmpty && !isEditingWording)

                Button {
                    if isEditingWording {
                        let trimmed = wordingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        customWording = trimmed.isEmpty ? nil : trimmed
                    } else {
                        wordingDraft = wording
                    }
                    isEditingWording.toggle()
                } label: {
                    Label(isEditingWording ? "Done" : "Edit", systemImage: isEditingWording ? "checkmark" : "pencil")
                }
                .disabled(taskTitle.isEmpty && !isEditingWording)

                if customWording != nil && !isEditingWording {
                    Button {
                        customWording = nil
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .accessibilityLabel("Reset wording")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Saving

    private func save() {
        guard canSave, let assignee = resolvedAssignee else { return }

        // Commit an edit that's still open, so "Add" doesn't silently drop it.
        if isEditingWording {
            let trimmed = wordingDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            customWording = trimmed.isEmpty ? nil : trimmed
        }

        let chore: Chore
        switch source {
        case .list:
            guard let picked = selectedChore else { return }
            chore = picked
        case .new:
            let created = Chore(
                title: taskTitle,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                category: category,
                recurrence: recurrence,
                difficulty: difficulty,
                labor: labor,
                minutes: minutes,
                proposerID: creator.id
            )
            created.household = household
            context.insert(created)
            // The chore has to reach the server before the task that points at it.
            HouseholdActions.choreSaved(created)
            chore = created
        }

        let handedOut = assigneeChoice == .furthestBehind
        let assignment = HouseholdActions.assign(
            chore: chore,
            to: assignee,
            due: dueDate,
            in: household,
            context: context,
            autoAssigned: handedOut,
            reason: handedOut ? "Fewest points in the household" : "Added by \(creator.shortName)",
            scheduleReminder: false
        )
        let remindHere = reminderOn && HouseholdActions.remindsOnThisPhone(for: assignee, in: household)
        assignment.reminderDate = remindHere ? reminderDate : nil
        assignment.voiceReminderEnabled = voiceOn
        assignment.reminderSpokenText = customWording
            ?? ReminderPhrase.sentence(for: assignment, assigneeName: assignee.name)
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        guard remindHere else {
            dismiss()
            return
        }

        let reminder = NotificationService.ReminderRequest(assignment: assignment, assigneeName: assignee.name)
        Task {
            let outcome = await NotificationService.shared.scheduleReminderRequestingPermission(reminder)
            await MainActor.run {
                if outcome == .permissionDenied {
                    permissionDenied = true
                } else {
                    dismiss()
                }
            }
        }
    }

    // MARK: - Dates

    /// Tonight at 8pm, or tomorrow at 8pm if tonight is less than an hour away — chores
    /// are evening work, and "due in 20 minutes" is not a helpful default.
    static func defaultDueDate(now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let tonight = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: now) ?? now
        if tonight.timeIntervalSince(now) >= 3600 { return tonight }
        return calendar.date(byAdding: .day, value: 1, to: tonight) ?? tonight
    }

    /// Two hours before it's due if there's time, then progressively closer, and never in
    /// the past.
    static func suggestedReminder(forDue due: Date, now: Date = Date()) -> Date {
        let earliest = now.addingTimeInterval(5 * 60)
        for offset in [-2 * 3600.0, -3600, -1800, 0] {
            let candidate = due.addingTimeInterval(offset)
            if candidate > earliest { return candidate }
        }
        return now.addingTimeInterval(15 * 60)
    }

    private var reminderPresets: [(label: String, date: Date)] {
        let calendar = Calendar.current
        let now = Date()
        var options: [(String, Date)] = [
            ("At due time", dueDate),
            ("30 min before", dueDate.addingTimeInterval(-1800)),
            ("1 hr before", dueDate.addingTimeInterval(-3600)),
            ("2 hrs before", dueDate.addingTimeInterval(-7200))
        ]
        if let morning = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dueDate) {
            options.append(("Morning of", morning))
        }
        if let dayBefore = calendar.date(byAdding: .day, value: -1, to: dueDate),
           let evening = calendar.date(bySettingHour: 19, minute: 0, second: 0, of: dayBefore) {
            options.append(("Evening before", evening))
        }
        return options
            .filter { $0.1 > now && $0.1 <= dueDate }
            .map { (label: $0.0, date: $0.1) }
    }

    private func isSameMinute(_ lhs: Date, _ rhs: Date) -> Bool {
        abs(lhs.timeIntervalSince(rhs)) < 60
    }
}
