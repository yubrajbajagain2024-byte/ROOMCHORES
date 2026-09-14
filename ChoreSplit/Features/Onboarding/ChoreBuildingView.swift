import SwiftUI
import SwiftData

/// The part the whole app rests on: the household builds the chore list together, then
/// anonymously re-rates each other's proposals so no one can quietly overprice their own.
struct ChoreBuildingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var household: Household

    private enum Round { case adding, calibrating }
    @State private var round: Round = .adding
    @State private var showingEditor = false
    @State private var showingStarters = false
    @State private var choreToRate: Chore?
    @State private var editingChore: Chore?

    private var members: [Roommate] { household.sortedMembers }
    private var activeMember: Roommate? { appState.activeRoommate(in: household) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SetupProgress(step: 3, total: 3)
                    .padding(.horizontal, -16)

                header

                passThePhoneStrip

                if let member = activeMember {
                    switch round {
                    case .adding:      addingSection(for: member)
                    case .calibrating: calibrationSection(for: member)
                    }
                }

                Spacer(minLength: 12)

                footerButton
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    if round == .calibrating {
                        round = .adding
                    } else {
                        household.setupStage = .roommates
                        try? context.save()
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            ChoreEditorView(household: household, author: activeMember)
        }
        .sheet(item: $editingChore) { chore in
            ChoreEditorView(household: household, author: activeMember, existing: chore)
        }
        .sheet(isPresented: $showingStarters) {
            StarterChorePickerView(household: household, author: activeMember)
        }
        .sheet(item: $choreToRate) { chore in
            if let member = activeMember {
                ChoreValueRatingView(chore: chore, household: household, rater: member)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(round == .adding ? "Build the chore list" : "Rate each other's chores")
                .font(.largeTitle.weight(.bold))
            Text(round == .adding
                 ? "Pass the phone around. Everyone adds the chores they think matter and says what each is worth."
                 : "Now rate what everyone else proposed — anonymously. The final value is the average, so nobody can price their own chore high and coast.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Whose turn

    private var passThePhoneStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Whose turn?")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(members) { member in
                        Button {
                            appState.activeRoommateID = member.id
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        } label: {
                            VStack(spacing: 6) {
                                AvatarView(
                                    roommate: member,
                                    size: 52,
                                    showsRing: member.id == activeMember?.id
                                )
                                Text(member.shortName)
                                    .font(.caption.weight(member.id == activeMember?.id ? .semibold : .regular))
                                    .foregroundStyle(member.id == activeMember?.id ? .primary : .secondary)
                                Text(badgeText(for: member))
                                    .font(.caption2)
                                    .foregroundStyle(isDone(member) ? Theme.green : .secondary)
                            }
                            .frame(width: 76)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .card()
    }

    private func badgeText(for member: Roommate) -> String {
        switch round {
        case .adding:
            let count = choresProposed(by: member).count
            return count == 0 ? "none yet" : "\(count) added"
        case .calibrating:
            let pending = unratedChores(for: member).count
            return pending == 0 ? "all rated" : "\(pending) to rate"
        }
    }

    private func isDone(_ member: Roommate) -> Bool {
        switch round {
        case .adding:      return !choresProposed(by: member).isEmpty
        case .calibrating: return unratedChores(for: member).isEmpty
        }
    }

    // MARK: - Round 1: adding

    private func addingSection(for member: Roommate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "\(member.shortName)'s chores",
                subtitle: "Add anything you think needs doing regularly"
            )

            HStack(spacing: 10) {
                Button {
                    showingEditor = true
                } label: {
                    Label("New chore", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showingStarters = true
                } label: {
                    Label("Pick from a list", systemImage: "list.bullet")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            let mine = choresProposed(by: member)
            if mine.isEmpty {
                EmptyStateView(
                    symbol: "sparkles",
                    title: "Nothing added yet",
                    message: "Start with the things that annoy you most when they don't get done."
                )
                .card()
            } else {
                VStack(spacing: 10) {
                    ForEach(mine) { chore in
                        ChoreSummaryRow(chore: chore, household: household, showsProposer: false)
                            .card(padding: 12)
                            .contentShape(Rectangle())
                            .onTapGesture { editingChore = chore }
                            .contextMenu {
                                Button("Edit") { editingChore = chore }
                                Button("Delete", role: .destructive) {
                                    context.delete(chore)
                                    try? context.save()
                                }
                            }
                    }
                }
            }

            if !allMembersHaveChores {
                Label(
                    "Everyone needs at least one chore on the list before you can move on.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Round 2: calibrating

    private func calibrationSection(for member: Roommate) -> some View {
        let pending = unratedChores(for: member)
        let rated = othersChores(for: member).count - pending.count

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "\(member.shortName)'s turn to rate",
                subtitle: "Your ratings are never shown next to your name",
                trailing: "\(rated)/\(othersChores(for: member).count)"
            )

            if pending.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Theme.green)
                    Text("All rated — pass the phone on.")
                        .font(.subheadline.weight(.medium))
                    Text("When everyone has been round, finish setup and ChoreSplit will do the first split.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .card()
            } else {
                VStack(spacing: 10) {
                    ForEach(pending) { chore in
                        Button {
                            choreToRate = chore
                        } label: {
                            HStack(spacing: 12) {
                                ChoreSummaryRow(chore: chore, household: household, showsProposer: true, hidePoints: true)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .card(padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footerButton: some View {
        switch round {
        case .adding:
            VStack(spacing: 8) {
                Button {
                    round = .calibrating
                    appState.activeRoommateID = members.first?.id
                } label: {
                    Text("Next: rate each other's chores")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!allMembersHaveChores)

                Text("\(household.activeChores.count) chores on the list")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .calibrating:
            VStack(spacing: 8) {
                Button(action: finishSetup) {
                    Text("Finish setup and split the chores")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if !everyoneHasRated {
                    Text("You can finish now — anything unrated just keeps its proposed value, and you can rate it later.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Data helpers

    private func choresProposed(by member: Roommate) -> [Chore] {
        household.activeChores.filter { $0.proposerID == member.id }
    }

    private func othersChores(for member: Roommate) -> [Chore] {
        household.activeChores.filter { $0.proposerID != member.id }
    }

    private func unratedChores(for member: Roommate) -> [Chore] {
        othersChores(for: member).filter { !$0.hasVoted(member) }
    }

    private var allMembersHaveChores: Bool {
        !members.isEmpty && members.allSatisfy { !choresProposed(by: $0).isEmpty }
    }

    private var everyoneHasRated: Bool {
        members.allSatisfy { unratedChores(for: $0).isEmpty }
    }

    // MARK: - Finishing

    private func finishSetup() {
        household.setupStage = .running
        household.cycleStartDate = Calendar.current.startOfDay(for: Date())
        appState.activeRoommateID = members.first?.id

        // First split of the cycle: heaviest chores placed first so the light ones can
        // even things out around them.
        let plan = FairnessEngine.openingPlan(for: household)
        HouseholdActions.apply(plan, in: household, context: context)
        try? context.save()

        Task { await NotificationService.shared.requestAuthorization() }
    }
}

/// Compact one-line summary of a chore, reused across setup and the chore library.
struct ChoreSummaryRow: View {
    let chore: Chore
    let household: Household
    var showsProposer: Bool = true
    var hidePoints: Bool = false

    private var proposer: Roommate? {
        household.sortedMembers.first { $0.id == chore.proposerID }
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(chore.category.tint.opacity(0.15))
                Image(systemName: chore.category.symbol)
                    .foregroundStyle(chore.category.tint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(chore.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(chore.recurrence.label)
                    if showsProposer, let proposer {
                        Text("·")
                        Text("added by \(proposer.shortName)")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if !hidePoints {
                PointsBadge(points: Double(chore.points), size: .small, tint: chore.category.tint)
            }
        }
    }
}
