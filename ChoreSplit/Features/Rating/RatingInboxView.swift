import SwiftUI
import SwiftData

/// Everything waiting on this roommate's anonymous verdict — both kinds of rating in one
/// place, because "rate a thing" is one habit, not two.
struct RatingInboxView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    let household: Household

    @State private var showingSwitcher = false
    @State private var assignmentToRate: Assignment?
    @State private var choreToRate: Chore?

    private var me: Roommate? { appState.activeRoommate(in: household) }

    /// Completed work by other people that I haven't rated yet.
    private var workToRate: [Assignment] {
        guard let me else { return [] }
        return (household.assignments ?? [])
            .filter { $0.status == .awaitingReview && $0.assignee?.id != me.id && !$0.hasRated(me) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    /// Chores someone else proposed that I haven't put a value on.
    private var valuesToRate: [Chore] {
        guard let me else { return [] }
        return household.activeChores
            .filter { $0.proposerID != me.id && !$0.hasVoted(me) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var recentlySettled: [Assignment] {
        (household.assignments ?? [])
            .filter { $0.status == .settled && $0.completedAt != nil }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Group {
                if workToRate.isEmpty && valuesToRate.isEmpty && recentlySettled.isEmpty {
                    EmptyStateView(
                        symbol: "hand.thumbsup",
                        title: "Nothing to rate",
                        message: "When someone finishes a chore you'll be asked how it went — anonymously."
                    )
                } else {
                    List {
                        anonymityNotice

                        if !workToRate.isEmpty {
                            Section {
                                ForEach(workToRate) { assignment in
                                    Button { assignmentToRate = assignment } label: {
                                        WorkToRateRow(assignment: assignment, household: household)
                                    }
                                    .buttonStyle(.plain)
                                }
                            } header: {
                                Label("How did they do?", systemImage: "checkmark.seal")
                            } footer: {
                                Text("Your score changes what the chore paid out. A 3 means \u{201C}done properly\u{201D} and pays the full value.")
                            }
                        }

                        if !valuesToRate.isEmpty {
                            Section {
                                ForEach(valuesToRate) { chore in
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
                                Label("What are these worth?", systemImage: "dial.medium")
                            } footer: {
                                Text("Rate the job itself, not the person. The point value ends up as the household average.")
                            }
                        }

                        if !recentlySettled.isEmpty {
                            Section {
                                ForEach(recentlySettled) { assignment in
                                    SettledRow(assignment: assignment, household: household)
                                }
                            } header: {
                                Label("Recently settled", systemImage: "clock.arrow.circlepath")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Rate")
            .toolbar {
                ActiveUserButton(household: household, showingSwitcher: $showingSwitcher, activeMember: me)
            }
            .sheet(isPresented: $showingSwitcher) {
                UserSwitcherSheet(household: household)
                    .presentationDetents([.medium])
            }
            .sheet(item: $assignmentToRate) { assignment in
                if let me {
                    QualityRatingView(assignment: assignment, household: household, rater: me)
                }
            }
            .sheet(item: $choreToRate) { chore in
                if let me {
                    ChoreValueRatingView(chore: chore, household: household, rater: me)
                }
            }
        }
    }

    private var anonymityNotice: some View {
        Section {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "eye.slash.fill")
                    .foregroundStyle(Theme.indigo)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Nobody sees who said what")
                        .font(.subheadline.weight(.semibold))
                    Text("Scores are only shown once \(household.minimumRatingsToReveal) people have rated, so a single rating can't be traced back by elimination.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct WorkToRateRow: View {
    let assignment: Assignment
    let household: Household

    var body: some View {
        HStack(spacing: 12) {
            if let assignee = assignment.assignee {
                AvatarView(roommate: assignee, size: 38)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if let assignee = assignment.assignee, let completedAt = assignment.completedAt {
                    Text("\(assignee.shortName) finished \(completedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

private struct SettledRow: View {
    let assignment: Assignment
    let household: Household

    var body: some View {
        HStack(spacing: 12) {
            if let assignee = assignment.assignee {
                AvatarView(roommate: assignee, size: 30)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(assignment.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if assignment.qualityIsRevealed(in: household), let average = assignment.averageQuality {
                    Text(PointsEngine.describeQuality(average))
                        .font(.caption2)
                        .foregroundStyle(Theme.qualityColor(average))
                } else {
                    Text("Paid face value")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            PointsBadge(points: assignment.effectivePoints, size: .small, tint: Theme.slate)
        }
    }
}
