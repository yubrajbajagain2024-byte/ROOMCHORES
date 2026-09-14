import SwiftUI
import SwiftData

/// Who is pulling their weight. Deliberately framed as distance from a fair share rather
/// than a high-score table — the goal is an even split, not a competition to do the most.
struct StandingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    let household: Household

    @State private var showingSwitcher = false
    @State private var showingBalanceSheet = false

    private var me: Roommate? { appState.activeRoommate(in: household) }
    private var standings: [MemberStanding] {
        FairnessEngine.standings(for: household).sorted { $0.percentOfTarget > $1.percentOfTarget }
    }
    private var behind: [MemberStanding] {
        standings.filter { $0.isBehind(tolerance: household.fairnessTolerance) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    cycleHeader

                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "This cycle",
                            subtitle: "Points carried against each person's fair share"
                        )
                        ForEach(standings) { standing in
                            StandingRow(
                                standing: standing,
                                household: household,
                                isMe: standing.roommate.id == me?.id
                            )
                            .card()
                        }
                    }

                    nextInLineCard

                    if !behind.isEmpty {
                        rebalanceCard
                    }

                    howItWorksCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Standings")
            .toolbar {
                ActiveUserButton(household: household, showingSwitcher: $showingSwitcher, activeMember: me)
            }
            .sheet(isPresented: $showingSwitcher) {
                UserSwitcherSheet(household: household)
                    .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingBalanceSheet) {
                RebalanceSheet(household: household)
            }
        }
    }

    // MARK: - Cards

    private var cycleHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Cycle ends in \(household.daysLeftInCycle) day\(household.daysLeftInCycle == 1 ? "" : "s")")
                        .font(.headline)
                    Text(cycleRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(totalPool.rounded()))")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("pts in play")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            HStack(spacing: 18) {
                miniStat("\(settledCount)", "done")
                miniStat("\(openCount)", "to do")
                miniStat("\(awaitingCount)", "being rated")
                Spacer()
            }
        }
        .card()
    }

    private var nextInLineCard: some View {
        Group {
            if let next = FairnessEngine.nextInLine(for: household) {
                HStack(spacing: 12) {
                    AvatarView(roommate: next, size: 42)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(next.shortName) is next in line")
                            .font(.subheadline.weight(.semibold))
                        Text("The next chore that comes up goes to whoever is furthest below their share — not to whoever's turn it technically is.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .card()
            }
        }
    }

    private var rebalanceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.amber)
                VStack(alignment: .leading, spacing: 3) {
                    Text(behind.count == 1
                         ? "\(behind[0].roommate.shortName) is behind"
                         : "\(behind.count) people are behind")
                        .font(.subheadline.weight(.semibold))
                    Text("ChoreSplit can hand out extra chores to close the gap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                showingBalanceSheet = true
            } label: {
                Text("Even it out")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
        .card()
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                .strokeBorder(Theme.amber.opacity(0.35), lineWidth: 1)
        )
    }

    private var howItWorksCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How the split works")
                .font(.subheadline.weight(.semibold))
            bullet("Every chore is worth points based on difficulty, physical effort and time — rated by the whole household, not just whoever added it.")
            bullet("Your fair share is the cycle's total points divided by how many people live here, adjusted for anyone on a reduced share.")
            bullet("Fall more than \(Int(household.fairnessTolerance * 100))% below your share and the app hands you extra chores until you catch up.")
            bullet("Anything still unbalanced when the cycle ends carries half the gap into the next one, so a slow week isn't simply wiped.")
        }
        .card()
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(Theme.indigo.opacity(0.4))
                .frame(width: 5, height: 5)
                .padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Derived

    private var cycleAssignments: [Assignment] { household.currentCycleAssignments }
    private var totalPool: Double {
        cycleAssignments.filter { $0.status != .skipped }.reduce(0) { $0 + $1.effectivePoints }
    }
    private var settledCount: Int { cycleAssignments.filter { $0.status == .settled }.count }
    private var openCount: Int { cycleAssignments.filter { $0.status == .open }.count }
    private var awaitingCount: Int { cycleAssignments.filter { $0.status == .awaitingReview }.count }

    private var cycleRangeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return "\(formatter.string(from: household.currentCycleStart)) – \(formatter.string(from: household.cycleEndDate))"
    }
}

// MARK: - Row

struct StandingRow: View {
    let standing: MemberStanding
    let household: Household
    var isMe: Bool = false

    private var tolerance: Double { household.fairnessTolerance }

    private var statusText: String {
        if standing.isBehind(tolerance: tolerance) {
            return "\(Int(standing.deficit.rounded())) pts behind"
        }
        if standing.isAhead(tolerance: tolerance) {
            return "\(Int((-standing.deficit).rounded())) pts ahead"
        }
        return "On track"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(roommate: standing.roommate, size: 40, showsRing: isMe)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(standing.roommate.name)
                            .font(.subheadline.weight(.semibold))
                        if isMe {
                            Text("you")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color(.tertiarySystemFill)))
                        }
                    }
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(Theme.balanceColor(percentOfTarget: standing.percentOfTarget))
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 0) {
                    Text("\(Int(standing.load.rounded()))")
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                    Text("of \(Int(standing.target.rounded()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            BalanceBar(percentOfTarget: standing.percentOfTarget)

            HStack(spacing: 12) {
                legend(color: Theme.green, text: "\(Int(standing.banked.rounded())) banked")
                if standing.provisional > 0 {
                    legend(color: Theme.amber, text: "\(Int(standing.provisional.rounded())) in progress")
                }
                if standing.roommate.shareWeight != 1.0 {
                    legend(color: Theme.slate, text: "\(Int(standing.roommate.shareWeight * 100))% share")
                }
                Spacer()
            }
        }
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Rebalance

/// Shows exactly what the app is about to hand out and to whom, before it does it.
/// Auto-assignment that happens silently is how a fairness app loses the household's trust.
struct RebalanceSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let household: Household

    @State private var plan: [ProposedAssignment] = []

    var body: some View {
        NavigationStack {
            Group {
                if plan.isEmpty {
                    EmptyStateView(
                        symbol: "checkmark.circle",
                        title: "Nothing to hand out",
                        message: "Either everyone is within tolerance, or there are no unassigned chores left to give."
                    )
                } else {
                    List {
                        Section {
                            ForEach(plan) { proposal in
                                HStack(spacing: 12) {
                                    AvatarView(roommate: proposal.roommate, size: 36)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(proposal.chore.title)
                                            .font(.subheadline.weight(.medium))
                                        Text(proposal.reason)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 4)
                                    PointsBadge(points: Double(proposal.chore.points), size: .small)
                                }
                            }
                        } header: {
                            Text("Proposed")
                        } footer: {
                            Text("Chores go to whoever is furthest below their share, largest first, and stop as soon as they're back inside tolerance.")
                        }
                    }
                }
            }
            .navigationTitle("Even it out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Assign \(plan.count)") {
                        HouseholdActions.apply(plan, in: household, context: context)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        dismiss()
                    }
                    .disabled(plan.isEmpty)
                }
            }
            .onAppear { plan = FairnessEngine.catchUpPlan(for: household) }
        }
    }
}
