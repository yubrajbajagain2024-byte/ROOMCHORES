import SwiftUI
import SwiftData

/// One chore on someone's list. Completion is a tap target on the row itself — burying
/// "done" behind a detail screen is the fastest way to get a chore app abandoned.
struct AssignmentRow: View {
    @Environment(\.modelContext) private var context

    let assignment: Assignment
    let household: Household
    var showsAssignee: Bool = false
    var compact: Bool = false
    var onComplete: (() -> Void)?

    private var chore: Chore? { assignment.chore }

    var body: some View {
        HStack(spacing: 12) {
            if let onComplete {
                Button(action: onComplete) {
                    Image(systemName: "circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Theme.indigo.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark \(assignment.title) done")
            } else if showsAssignee, let assignee = assignment.assignee {
                AvatarView(roommate: assignee, size: 34)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill((chore?.category.tint ?? Theme.slate).opacity(0.15))
                    Image(systemName: chore?.category.symbol ?? "square")
                        .foregroundStyle(chore?.category.tint ?? Theme.slate)
                        .font(.footnote)
                }
                .frame(width: 34, height: 34)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Label(assignment.dueDescription, systemImage: "calendar")
                        .foregroundStyle(assignment.isOverdue ? Theme.rose : .secondary)

                    if showsAssignee, let assignee = assignment.assignee {
                        Text("·")
                        Text(assignee.shortName)
                    }

                    if assignment.reminderDate != nil && assignment.voiceReminderEnabled {
                        Text("·")
                        Image(systemName: "waveform")
                            .foregroundStyle(Theme.violet)
                            .accessibilityLabel("Voice reminder set")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if !compact, assignment.wasAutoAssigned, !assignment.assignmentReason.isEmpty {
                    Text(assignment.assignmentReason)
                        .font(.caption2)
                        .foregroundStyle(Theme.amber)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            PointsBadge(
                points: assignment.effectivePoints,
                provisional: assignment.pointsAreProvisional,
                size: .small,
                tint: chore?.category.tint ?? Theme.indigo
            )
        }
        .contextMenu {
            if onComplete != nil {
                Button {
                    onComplete?()
                } label: {
                    Label("Mark done", systemImage: "checkmark.circle")
                }
                Button(role: .destructive) {
                    HouseholdActions.markSkipped(assignment, context: context)
                } label: {
                    Label("Skip this one", systemImage: "xmark.circle")
                }
            }
        }
    }
}

/// A chore you have finished that is waiting on anonymous peer ratings before the
/// points are banked.
struct AwaitingReviewRow: View {
    let assignment: Assignment
    let household: Household

    private var raterCount: Int { assignment.eligibleRaters(in: household).count }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.amber.opacity(0.15))
                Image(systemName: "hourglass")
                    .foregroundStyle(Theme.amber)
                    .font(.footnote)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(.subheadline.weight(.medium))
                Text(statusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            PointsBadge(points: assignment.effectivePoints, provisional: true, size: .small, tint: Theme.amber)
        }
    }

    private var statusText: String {
        let rated = assignment.ratings.count
        if rated == 0 {
            return "No ratings in yet · \(raterCount) housemate\(raterCount == 1 ? "" : "s") can rate"
        }
        return "\(rated) of \(raterCount) ratings in"
    }
}
