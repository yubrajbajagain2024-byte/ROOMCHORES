import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    let household: Household

    @State private var showingSwitcher = false
    @State private var selectedAssignment: Assignment?
    @State private var showingClaimSheet = false

    private var me: Roommate? { appState.activeRoommate(in: household) }

    private var myOpen: [Assignment] {
        guard let me else { return [] }
        return (household.assignments ?? [])
            .filter { $0.status == .open && $0.assignee?.id == me.id }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var myAwaitingReview: [Assignment] {
        guard let me else { return [] }
        return (household.assignments ?? [])
            .filter { $0.status == .awaitingReview && $0.assignee?.id == me.id }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var othersOpen: [Assignment] {
        guard let me else { return [] }
        return (household.assignments ?? [])
            .filter { $0.status == .open && $0.assignee?.id != me.id }
            .sorted { $0.dueDate < $1.dueDate }
    }

    private var myStanding: MemberStanding? {
        guard let me else { return nil }
        return FairnessEngine.standings(for: household).first { $0.roommate.id == me.id }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let standing = myStanding {
                        BalanceCard(standing: standing, household: household)
                    }

                    autoAssignedBanner

                    mySection

                    if !myAwaitingReview.isEmpty {
                        awaitingSection
                    }

                    if !othersOpen.isEmpty {
                        othersSection
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(household.name)
            .toolbar {
                ActiveUserButton(household: household, showingSwitcher: $showingSwitcher, activeMember: me)
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingClaimSheet = true
                    } label: {
                        Image(systemName: "hand.raised")
                    }
                    .accessibilityLabel("Claim a chore")
                }
            }
            .sheet(isPresented: $showingSwitcher) {
                UserSwitcherSheet(household: household)
                    .presentationDetents([.medium])
            }
            .sheet(item: $selectedAssignment) { assignment in
                AssignmentDetailView(assignment: assignment, household: household)
            }
            .sheet(isPresented: $showingClaimSheet) {
                if let me {
                    ClaimChoreSheet(household: household, claimant: me)
                }
            }
            .onChange(of: appState.pendingAssignmentID) { _, id in
                guard let id,
                      let match = (household.assignments ?? []).first(where: { $0.id == id })
                else { return }
                selectedAssignment = match
                appState.pendingAssignmentID = nil
            }
            .refreshable {
                HouseholdActions.runMaintenance(for: household, context: context)
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var autoAssignedBanner: some View {
        let fresh = myOpen.filter { $0.wasAutoAssigned && !$0.assignmentReason.isEmpty }
        if !fresh.isEmpty, let standing = myStanding, standing.isBehind(tolerance: household.fairnessTolerance) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.title3)
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text("You've been given extra chores")
                        .font(.subheadline.weight(.semibold))
                    Text("You're \(Int(standing.deficit.rounded())) points below your share this cycle, so ChoreSplit topped you up. Finish them and it evens out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1)
            )
        }
    }

    private var mySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Your chores",
                subtitle: myOpen.isEmpty ? nil : "\(myOpen.count) to do",
                trailing: "\(Int(myOpen.reduce(0) { $0 + $1.effectivePoints })) pts on the table"
            )

            if myOpen.isEmpty {
                EmptyStateView(
                    symbol: "checkmark.circle",
                    title: "Nothing on your list",
                    message: "You're clear for now. Claim a chore if you want to build up a buffer.",
                    actionTitle: "Claim a chore",
                    action: { showingClaimSheet = true }
                )
                .card()
            } else {
                ForEach(myOpen) { assignment in
                    AssignmentRow(
                        assignment: assignment,
                        household: household,
                        showsAssignee: false,
                        onComplete: { complete(assignment) }
                    )
                    .card(padding: 12)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedAssignment = assignment }
                }
            }
        }
    }

    private var awaitingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Waiting on ratings",
                subtitle: "Points settle once your housemates weigh in"
            )
            ForEach(myAwaitingReview) { assignment in
                AwaitingReviewRow(assignment: assignment, household: household)
                    .card(padding: 12)
                    .contentShape(Rectangle())
                    .onTapGesture { selectedAssignment = assignment }
            }
        }
    }

    private var othersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Everyone else", subtitle: "What the rest of the flat is on")
            ForEach(othersOpen.prefix(8)) { assignment in
                AssignmentRow(assignment: assignment, household: household, showsAssignee: true, compact: true)
                    .card(padding: 12)
            }
        }
    }

    private func complete(_ assignment: Assignment) {
        withAnimation {
            HouseholdActions.markComplete(assignment, in: household, context: context)
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - Balance card

struct BalanceCard: View {
    let standing: MemberStanding
    let household: Household

    private var tolerance: Double { household.fairnessTolerance }

    private var statusText: String {
        if standing.isBehind(tolerance: tolerance) {
            return "\(Int(standing.deficit.rounded())) points behind your share"
        }
        if standing.isAhead(tolerance: tolerance) {
            return "\(Int((-standing.deficit).rounded())) points ahead — nicely done"
        }
        return "Pulling your weight"
    }

    private var statusSymbol: String {
        if standing.isBehind(tolerance: tolerance) { return "arrow.down.right" }
        if standing.isAhead(tolerance: tolerance) { return "arrow.up.right" }
        return "equal"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AvatarView(roommate: standing.roommate, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(standing.roommate.name).font(.headline)
                    Label(statusText, systemImage: statusSymbol)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.balanceColor(percentOfTarget: standing.percentOfTarget))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(standing.load.rounded()))")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .contentTransition(.numericText())
                    Text("of \(Int(standing.target.rounded())) pts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            BalanceBar(percentOfTarget: standing.percentOfTarget, height: 10)

            HStack(spacing: 16) {
                statPill(label: "Banked", value: standing.banked, color: Theme.green)
                statPill(label: "In progress", value: standing.provisional, color: Theme.amber)
                if standing.carryOver != 0 {
                    statPill(
                        label: standing.carryOver > 0 ? "Owed from last cycle" : "Credit carried over",
                        value: abs(standing.carryOver),
                        color: Theme.slate
                    )
                }
                Spacer()
            }

            Divider()

            HStack {
                Label("\(household.daysLeftInCycle) days left in this cycle", systemImage: "calendar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .card()
    }

    private func statPill(label: String, value: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
