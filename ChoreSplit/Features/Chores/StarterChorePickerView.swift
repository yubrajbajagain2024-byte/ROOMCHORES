import SwiftUI
import SwiftData

/// Quick-add from a starter library, so setup does not start on a blank page.
struct StarterChorePickerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let household: Household
    let author: Roommate?

    @State private var selected: Set<String> = []

    private var existingTitles: Set<String> {
        Set(household.activeChores.map { $0.title.lowercased() })
    }

    private var grouped: [(ChoreCategory, [StarterChore])] {
        let available = StarterChores.suggestions(excluding: existingTitles)
        return ChoreCategory.allCases.compactMap { category in
            let items = available.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if grouped.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.circle",
                        title: "All added",
                        message: "Every suggestion is already on your list. Add anything else with the New chore button."
                    )
                } else {
                    List {
                        ForEach(grouped, id: \.0) { category, items in
                            Section {
                                ForEach(items, id: \.title) { starter in
                                    row(for: starter)
                                }
                            } header: {
                                Label(category.label, systemImage: category.symbol)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Common chores")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(selected.isEmpty ? "Add" : "Add \(selected.count)", action: addSelected)
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func row(for starter: StarterChore) -> some View {
        let isSelected = selected.contains(starter.title)
        let points = PointsEngine.points(for: ChoreValues(
            difficulty: Double(starter.difficulty),
            labor: Double(starter.labor),
            minutes: Double(starter.minutes)
        ))

        return Button {
            if isSelected { selected.remove(starter.title) } else { selected.insert(starter.title) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.indigo : Color.secondary)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(starter.title)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Text("\(starter.recurrence.label) · about \(starter.minutes) min")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 4)

                PointsBadge(points: Double(points), size: .small, tint: starter.category.tint)
            }
        }
        .buttonStyle(.plain)
    }

    private func addSelected() {
        for starter in StarterChores.all where selected.contains(starter.title) {
            let chore = Chore(
                title: starter.title,
                category: starter.category,
                recurrence: starter.recurrence,
                difficulty: starter.difficulty,
                labor: starter.labor,
                minutes: starter.minutes,
                proposerID: author?.id
            )
            chore.household = household
            context.insert(chore)
        }
        try? context.save()
        dismiss()
    }
}
