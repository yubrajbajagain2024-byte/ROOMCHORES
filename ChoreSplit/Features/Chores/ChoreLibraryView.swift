import SwiftUI
import SwiftData

/// Every chore the household has agreed on, and what each is currently worth.
struct ChoreLibraryView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    let household: Household

    @State private var showingEditor = false
    @State private var showingStarters = false
    @State private var showingSwitcher = false
    @State private var editingChore: Chore?
    @State private var choreToRate: Chore?
    @State private var searchText = ""
    @State private var categoryFilter: ChoreCategory?

    private var me: Roommate? { appState.activeRoommate(in: household) }

    private var filtered: [Chore] {
        household.activeChores.filter { chore in
            let matchesSearch = searchText.isEmpty
                || chore.title.localizedCaseInsensitiveContains(searchText)
                || chore.notes.localizedCaseInsensitiveContains(searchText)
            let matchesCategory = categoryFilter == nil || chore.category == categoryFilter
            return matchesSearch && matchesCategory
        }
    }

    private var grouped: [(ChoreCategory, [Chore])] {
        ChoreCategory.allCases.compactMap { category in
            let items = filtered.filter { $0.category == category }.sorted { $0.points > $1.points }
            return items.isEmpty ? nil : (category, items)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if household.activeChores.isEmpty {
                    EmptyStateView(
                        symbol: "square.grid.2x2",
                        title: "No chores yet",
                        message: "Add the jobs that need doing regularly. Everyone rates them afterwards to settle what each is worth.",
                        actionTitle: "Add a chore",
                        action: { showingEditor = true }
                    )
                } else {
                    List {
                        summaryRow

                        if !unratedByMe.isEmpty {
                            Section {
                                ForEach(unratedByMe) { chore in
                                    Button { choreToRate = chore } label: {
                                        HStack {
                                            ChoreSummaryRow(chore: chore, household: household, hidePoints: true)
                                            Image(systemName: "chevron.right")
                                                .font(.caption.weight(.semibold))
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Label("Waiting on your rating", systemImage: "dial.medium")
                            } footer: {
                                Text("Your numbers are folded into the household average without your name on them.")
                            }
                        }

                        ForEach(grouped, id: \.0) { category, chores in
                            Section {
                                ForEach(chores) { chore in
                                    NavigationLink {
                                        ChoreDetailView(chore: chore, household: household)
                                    } label: {
                                        ChoreLibraryRow(chore: chore, household: household)
                                    }
                                    .swipeActions(edge: .trailing) {
                                        Button(role: .destructive) {
                                            retire(chore)
                                        } label: {
                                            Label("Retire", systemImage: "archivebox")
                                        }
                                        Button {
                                            editingChore = chore
                                        } label: {
                                            Label("Edit", systemImage: "pencil")
                                        }
                                        .tint(Theme.slate)
                                    }
                                }
                            } header: {
                                Label(category.label, systemImage: category.symbol)
                            }
                        }
                    }
                    .searchable(text: $searchText, prompt: "Search chores")
                }
            }
            .navigationTitle("Chores")
            .toolbar {
                ActiveUserButton(household: household, showingSwitcher: $showingSwitcher, activeMember: me)
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showingEditor = true
                        } label: {
                            Label("New chore", systemImage: "plus")
                        }
                        Button {
                            showingStarters = true
                        } label: {
                            Label("Pick from common chores", systemImage: "list.bullet")
                        }
                        Divider()
                        Picker("Filter", selection: $categoryFilter) {
                            Text("All areas").tag(ChoreCategory?.none)
                            ForEach(ChoreCategory.allCases) { category in
                                Label(category.label, systemImage: category.symbol)
                                    .tag(ChoreCategory?.some(category))
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                ChoreEditorView(household: household, author: me)
            }
            .sheet(isPresented: $showingStarters) {
                StarterChorePickerView(household: household, author: me)
            }
            .sheet(item: $editingChore) { chore in
                ChoreEditorView(household: household, author: me, existing: chore)
            }
            .sheet(item: $choreToRate) { chore in
                if let me {
                    ChoreValueRatingView(chore: chore, household: household, rater: me)
                }
            }
            .sheet(isPresented: $showingSwitcher) {
                UserSwitcherSheet(household: household)
                    .presentationDetents([.medium])
            }
        }
    }

    private var unratedByMe: [Chore] {
        guard let me else { return [] }
        return household.activeChores.filter { $0.proposerID != me.id && !$0.hasVoted(me) }
    }

    private var summaryRow: some View {
        Section {
            HStack(spacing: 20) {
                stat("\(household.activeChores.count)", "chores")
                stat("\(totalCyclePoints)", "pts a cycle")
                stat("\(Int(fairShare))", "each")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
    }

    private var totalCyclePoints: Int {
        Int(household.activeChores.reduce(0.0) { $0 + $1.cycleWeight(cycleDays: household.cycleLengthDays) }.rounded())
    }

    private var fairShare: Double {
        let weights = household.sortedMembers.reduce(0.0) { $0 + max(0.01, $1.shareWeight) }
        guard weights > 0 else { return 0 }
        return Double(totalCyclePoints) / weights
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.indigo)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Retiring keeps the history intact; deleting would rewrite past scores.
    private func retire(_ chore: Chore) {
        chore.isActive = false
        try? context.save()
    }
}

struct ChoreLibraryRow: View {
    let chore: Chore
    let household: Household

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(chore.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(chore.recurrence.label)
                    if chore.votes.isEmpty {
                        Text("· unrated")
                            .foregroundStyle(Theme.amber)
                    } else {
                        Text("· \(chore.votes.count) rating\(chore.votes.count == 1 ? "" : "s")")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                PointsBadge(points: Double(chore.points), size: .small, tint: chore.category.tint)
                if chore.valuesAreRevealed(in: household), chore.pointDrift != 0 {
                    Text(chore.pointDrift > 0 ? "+\(chore.pointDrift)" : "\(chore.pointDrift)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(chore.pointDrift > 0 ? Theme.green : Theme.rose)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
