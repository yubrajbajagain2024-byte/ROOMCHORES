import SwiftUI
import SwiftData

/// Create or edit a chore. The three scales feed the point value live, so you can see
/// what you are claiming the job is worth while you are claiming it.
struct ChoreEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let household: Household
    let author: Roommate?
    /// Existing chore when editing; `nil` when creating.
    var existing: Chore?

    @State private var title = ""
    @State private var notes = ""
    @State private var category: ChoreCategory = .other
    @State private var recurrence: Recurrence = .weekly
    @State private var difficulty = 3
    @State private var labor = 2
    @State private var minutes = 15
    @FocusState private var titleFocused: Bool

    private var values: ChoreValues {
        ChoreValues(difficulty: Double(difficulty), labor: Double(labor), minutes: Double(minutes))
    }
    private var points: Int { PointsEngine.points(for: values) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("What's the chore?", text: $title)
                        .focused($titleFocused)
                    TextField("Notes — anything the next person needs to know", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("The job")
                }

                Section {
                    Picker("Area", selection: $category) {
                        ForEach(ChoreCategory.allCases) { option in
                            Label(option.label, systemImage: option.symbol).tag(option)
                        }
                    }
                    Picker("How often", selection: $recurrence) {
                        ForEach(Recurrence.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
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

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Time", systemImage: "clock")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(minutes) min")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.amber)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(minutes) },
                                set: { minutes = Int(($0 / 5).rounded() * 5) }
                            ),
                            in: 5...120,
                            step: 5
                        )
                        .tint(Theme.amber)
                        HStack {
                            Text("5 min")
                            Spacer()
                            Text("2 hours")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("What it takes")
                } footer: {
                    Text("Three scales, because a chore can be quick but disgusting, or long but easy. Scoring on time alone would under-pay scrubbing the toilet.")
                }

                Section {
                    PointsPreview(values: values, points: points)
                } header: {
                    Text("Worth")
                } footer: {
                    Text(author == nil
                         ? "Your housemates rate this anonymously afterwards, and the value settles on the household average."
                         : "This is your proposal. Everyone else rates it anonymously, and the final value is the average — so you can't quietly overprice your own chore.")
                }
            }
            .navigationTitle(existing == nil ? "New chore" : "Edit chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard let existing else {
            titleFocused = true
            return
        }
        title = existing.title
        notes = existing.notes
        category = existing.category
        recurrence = existing.recurrence
        difficulty = existing.proposedDifficulty
        labor = existing.proposedLabor
        minutes = existing.proposedMinutes
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        if let existing {
            existing.title = trimmed
            existing.notes = notes
            existing.category = category
            existing.recurrence = recurrence
            existing.proposedDifficulty = difficulty
            existing.proposedLabor = labor
            existing.proposedMinutes = minutes
        } else {
            let chore = Chore(
                title: trimmed,
                notes: notes,
                category: category,
                recurrence: recurrence,
                difficulty: difficulty,
                labor: labor,
                minutes: minutes,
                proposerID: author?.id
            )
            chore.household = household
            context.insert(chore)
        }
        try? context.save()
        dismiss()
    }
}

/// The live "this is worth N points" panel, broken down by what drove it.
struct PointsPreview: View {
    let values: ChoreValues
    let points: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(points)")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.indigo)
                    .contentTransition(.numericText())
                Text("points")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .animation(.snappy, value: points)

            let parts = PointsEngine.breakdown(for: values)
            let total = max(0.001, parts.reduce(0) { $0 + max(0, $1.points) })

            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(barColor(index))
                            .frame(width: max(2, geo.size.width * (max(0, part.points) / total)))
                    }
                }
            }
            .frame(height: 8)

            HStack(spacing: 14) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    HStack(spacing: 4) {
                        Circle().fill(barColor(index)).frame(width: 7, height: 7)
                        Text(part.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func barColor(_ index: Int) -> Color {
        [Theme.violet, Theme.teal, Theme.amber][index % 3]
    }
}
