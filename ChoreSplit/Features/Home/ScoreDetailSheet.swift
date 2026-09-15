import SwiftUI
import SwiftData

/// One roommate's points, task by task: what each finished task was worth, what it actually
/// paid, and why — ratings in, ratings pending, or too few ratings to show.
struct ScoreDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let roommate: Roommate
    let household: Household
    let isMe: Bool

    private var completed: [Assignment] { Scores.completedTasks(by: roommate, in: household) }
    private var thisCycle: [Assignment] { completed.filter { Scores.isInCurrentCycle($0, household: household) } }
    private var earlier: [Assignment] { completed.filter { !Scores.isInCurrentCycle($0, household: household) } }
    private var cycleLabel: String { household.cycleLengthDays == 7 ? "This week" : "This cycle" }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                profileHeader

                if completed.isEmpty {
                    Text(isMe ? "You haven't finished any tasks yet." : "\(roommate.shortName) hasn't finished any tasks yet.")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                        .background(Theme.feedCard)
                } else {
                    taskSection(title: cycleLabel, tasks: thisCycle, emptyText: "Nothing finished yet \(cycleLabel.lowercased()).")
                    if !earlier.isEmpty {
                        taskSection(title: "Earlier", tasks: earlier, emptyText: nil)
                    }
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.feedBackground)
        .presentationDragIndicator(.visible)
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                LinearGradient(
                    colors: [roommate.color.opacity(0.7), roommate.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: 120)

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(.black.opacity(0.3)))
                }
                .padding(12)
                .accessibilityLabel("Close")
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 12) {
                    ZStack {
                        Circle().fill(roommate.color.gradient)
                        Text(roommate.emoji).font(.system(size: 44))
                    }
                    .frame(width: 92, height: 92)
                    .overlay(Circle().strokeBorder(Theme.feedCard, lineWidth: 4))
                    .offset(y: -46)
                    .padding(.bottom, -46)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(roommate.name)
                            .font(.system(size: 24, weight: .bold))
                        if isMe {
                            Text("You").font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    stat(value: PointsEngine.format(Scores.total(thisCycle)), label: "pts \(cycleLabel.lowercased())")
                    stat(value: PointsEngine.format(Scores.total(completed)), label: "pts all time")
                    stat(value: "\(thisCycle.count)", label: "tasks \(cycleLabel.lowercased())")
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 16)
        }
        .background(Theme.feedCard)
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.chipFill))
    }

    // MARK: - Tasks

    private func taskSection(title: String, tasks: [Assignment], emptyText: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedSectionHeader(title: title, subtitle: tasks.isEmpty ? nil : "\(PointsEngine.format(Scores.total(tasks))) pts from \(tasks.count) task\(tasks.count == 1 ? "" : "s")")
                .padding(.bottom, 8)

            if tasks.isEmpty, let emptyText {
                Text(emptyText)
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 66)
                }
                EarnedTaskRow(assignment: task, household: household)
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }
}

/// One finished task and exactly how its points came out.
private struct EarnedTaskRow: View {
    let assignment: Assignment
    let household: Household

    private var earned: Double { assignment.effectivePoints }
    private var reduced: Bool { !assignment.pointsAreProvisional && earned < Double(assignment.pointsQuoted) }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            let category = assignment.chore?.category ?? .other
            ZStack {
                Circle().fill(category.tint.opacity(0.15))
                Image(systemName: category.symbol)
                    .font(.system(size: 16))
                    .foregroundStyle(category.tint)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(assignment.title)
                    .font(.system(size: 16, weight: .semibold))
                if let completedAt = assignment.completedAt {
                    Text("Finished \(completedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
                ratingLine
                notes
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(PointsEngine.format(earned))")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(assignment.pointsAreProvisional ? Theme.secondaryText : (reduced ? Theme.amber : Theme.green))
                    .monospacedDigit()
                Text(reduced ? "of \(assignment.pointsQuoted) pts" : "pts")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var ratingLine: some View {
        let raters = assignment.eligibleRaters(in: household).count
        let count = assignment.ratingCount

        switch assignment.status {
        case .awaitingReview:
            Label("Being rated · \(count) of \(raters) in — points not final", systemImage: "hourglass")
                .font(.system(size: 13))
                .foregroundStyle(Theme.amber)
        default:
            if let average = assignment.revealedAverage(in: household) {
                Label("\(String(format: "%.1f", average)) stars · \(PointsEngine.describeQuality(average))", systemImage: "star.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.qualityColor(average))
            } else if count == 0 {
                Label("No ratings — paid full points", systemImage: "equal.circle")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                // Showing one lone rating would reveal who gave it.
                Label("Too few ratings to show", systemImage: "lock.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var notes: some View {
        let texts = assignment.revealedNotes(in: household)
        if !texts.isEmpty {
            ForEach(Array(texts.enumerated()), id: \.offset) { _, text in
                Text("\u{201C}\(text)\u{201D}")
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(.primary.opacity(0.8))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chipFill))
            }
        }
    }
}
