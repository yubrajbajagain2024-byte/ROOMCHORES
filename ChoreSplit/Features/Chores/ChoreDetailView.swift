import SwiftUI
import SwiftData

struct ChoreDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @Bindable var chore: Chore
    let household: Household

    @State private var showingRating = false
    @State private var showingEditor = false

    private var me: Roommate? { appState.activeRoommate(in: household) }
    private var proposer: Roommate? {
        household.sortedMembers.first { $0.id == chore.proposerID }
    }
    private var history: [Assignment] {
        (chore.assignments ?? [])
            .filter { $0.status == .settled }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        CategoryChip(category: chore.category)
                        Text(chore.recurrence.label)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                    if !chore.notes.isEmpty {
                        Text(chore.notes).font(.subheadline)
                    }
                    if let proposer {
                        Label("Added by \(proposer.name)", systemImage: "person")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                PointsPreview(values: chore.agreedValues, points: chore.points)
            } header: {
                Text("Agreed value")
            } footer: {
                Text(valueFooter)
            }

            if chore.valuesAreRevealed(in: household) {
                Section {
                    comparisonRow(
                        "Difficulty",
                        proposed: chore.proposedValues.difficulty,
                        agreed: chore.agreedValues.difficulty,
                        suffix: "/5"
                    )
                    comparisonRow(
                        "Physical effort",
                        proposed: chore.proposedValues.labor,
                        agreed: chore.agreedValues.labor,
                        suffix: "/5"
                    )
                    comparisonRow(
                        "Time",
                        proposed: chore.proposedValues.minutes,
                        agreed: chore.agreedValues.minutes,
                        suffix: " min"
                    )
                    LabeledContent("Points") {
                        HStack(spacing: 6) {
                            Text("\(chore.proposedPoints)").foregroundStyle(.secondary)
                            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                            Text("\(chore.points)").fontWeight(.semibold)
                        }
                    }
                } header: {
                    Text("Proposed vs. what the household said")
                } footer: {
                    Text(chore.pointDrift == 0
                         ? "The household agreed with the original estimate."
                         : chore.pointDrift > 0
                           ? "Your housemates rated this harder than proposed, so it's worth \(chore.pointDrift) points more."
                           : "Your housemates rated this easier than proposed, so it's worth \(abs(chore.pointDrift)) points less.")
                }
            }

            Section {
                if let me, chore.proposerID == me.id {
                    Label("You added this one — you don't rate your own chores.", systemImage: "person.crop.circle.badge.checkmark")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let me, chore.hasVoted(me) {
                    Label("You've rated this. Your numbers are in the average.", systemImage: "checkmark.seal")
                        .font(.subheadline)
                        .foregroundStyle(Theme.green)
                } else {
                    Button {
                        showingRating = true
                    } label: {
                        Label("Rate what this is worth", systemImage: "dial.medium")
                    }
                }

                LabeledContent("Ratings in") {
                    Text("\(chore.votes.count) of \(max(0, household.sortedMembers.count - 1))")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Anonymous rating")
            }

            Section {
                Button {
                    assignToNextInLine()
                } label: {
                    Label("Assign to whoever's furthest behind", systemImage: "arrow.triangle.branch")
                }
                .disabled(isCurrentlyAssigned)

                if isCurrentlyAssigned {
                    Label("Already on someone's list", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !history.isEmpty {
                Section {
                    ForEach(history.prefix(10)) { assignment in
                        HStack(spacing: 10) {
                            if let assignee = assignment.assignee {
                                AvatarView(roommate: assignee, size: 28)
                                Text(assignee.shortName).font(.subheadline)
                            }
                            Spacer()
                            if let completedAt = assignment.completedAt {
                                Text(completedAt, format: .dateTime.day().month())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            PointsBadge(points: assignment.effectivePoints, size: .small, tint: Theme.slate)
                        }
                    }
                } header: {
                    Text("Who's done this before")
                }
            }
        }
        .navigationTitle(chore.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEditor = true }
            }
        }
        .sheet(isPresented: $showingRating) {
            if let me {
                ChoreValueRatingView(chore: chore, household: household, rater: me)
            }
        }
        .sheet(isPresented: $showingEditor) {
            ChoreEditorView(household: household, author: proposer, existing: chore)
        }
    }

    private var valueFooter: String {
        if chore.valuesAreRevealed(in: household) {
            return "Averaged across \(chore.votes.count) anonymous rating\(chore.votes.count == 1 ? "" : "s") plus the original proposal."
        }
        return "Still the proposer's estimate. It needs \(household.minimumRatingsToReveal) ratings before the household's view is shown."
    }

    private var isCurrentlyAssigned: Bool {
        (chore.assignments ?? []).contains { $0.status == .open }
    }

    private func comparisonRow(_ label: String, proposed: Double, agreed: Double, suffix: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                Text(format(proposed) + suffix).foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary)
                Text(format(agreed) + suffix).fontWeight(.medium)
            }
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }

    private func assignToNextInLine() {
        guard let next = FairnessEngine.nextInLine(for: household) else { return }
        HouseholdActions.assign(
            chore: chore,
            to: next,
            due: FairnessEngine.defaultDueDate(for: chore, in: household),
            in: household,
            context: context,
            autoAssigned: true,
            reason: "Lowest points in the household right now"
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
