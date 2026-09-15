import SwiftUI
import SwiftData

/// A roommate's finished task, rated right in the feed. Stars decide what the task pays;
/// the rating is stored against a salted hash, never your name.
struct RateTaskCard: View {
    @Environment(\.modelContext) private var context

    let assignment: Assignment
    let household: Household
    let rater: Roommate

    @State private var score = 0
    @State private var note = ""
    @FocusState private var noteFocused: Bool

    private var assigneeName: String { assignment.assignee?.name ?? "Someone" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(alignment: .leading, spacing: 8) {
                Text(assignment.title)
                    .font(.system(size: 17, weight: .semibold))
                HStack(spacing: 6) {
                    if let chore = assignment.chore {
                        Label(chore.category.label, systemImage: chore.category.symbol)
                            .foregroundStyle(chore.category.tint)
                    }
                    Text("·").foregroundStyle(Theme.secondaryText)
                    Text("Worth \(assignment.pointsQuoted) pts")
                        .foregroundStyle(Theme.secondaryText)
                }
                .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 14)

            if let videoURL = assignment.proofVideoURL {
                ProofVideoThumbnail(url: videoURL, duration: assignment.proofVideoDuration)
            } else if let path = assignment.proofVideoRemotePath {
                RemoteProofVideo(path: path, duration: assignment.proofVideoDuration)
            } else {
                Label("No video attached", systemImage: "video.slash")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 14)
            }

            Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.horizontal, 14)

            stars

            if score > 0 {
                noteAndSubmit
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.snappy, value: score)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            if let assignee = assignment.assignee {
                AvatarView(roommate: assignee, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                (Text(assigneeName).fontWeight(.semibold) + Text(" finished a task"))
                    .font(.system(size: 15))
                HStack(spacing: 4) {
                    Text(assignment.completedAt?.shortRelative ?? "")
                    Text("·")
                    Image(systemName: "lock.fill").font(.system(size: 10))
                    Text("Anonymous")
                }
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    // MARK: - Stars

    private var stars: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(1...5, id: \.self) { value in
                    Button {
                        score = value
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        Image(systemName: value <= score ? "star.fill" : "star")
                            .font(.system(size: 28))
                            .foregroundStyle(value <= score ? Theme.amber : Theme.secondaryText.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                            .contentShape(Rectangle())
                            .symbolEffect(.bounce, value: score == value)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                }
            }
            .padding(.horizontal, 24)

            Text(caption)
                .font(.system(size: 13))
                .foregroundStyle(score == 0 ? Theme.secondaryText : Theme.qualityColor(Double(score)))
                .contentTransition(.opacity)
        }
    }

    private var caption: String {
        guard score > 0 else {
            return "Watch the video, then rate it. 3 stars or more pays the full \(assignment.pointsQuoted) pts."
        }
        let pays = PointsEngine.settledPoints(quoted: assignment.pointsQuoted, averageQuality: Double(score))
        return "\(PointsEngine.describeQuality(Double(score))) · your rating pays \(PointsEngine.format(pays)) pts"
    }

    // MARK: - Note and submit

    private var noteAndSubmit: some View {
        HStack(spacing: 8) {
            TextField("Add an anonymous note…", text: $note, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(1...3)
                .focused($noteFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.chipFill))

            Button(action: submit) {
                Text("Submit")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 36)
                    .background(Capsule().fill(Theme.brand))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
    }

    private func submit() {
        guard score > 0 else { return }
        noteFocused = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.snappy) {
            HouseholdActions.submitQualityRating(
                for: assignment,
                by: rater,
                score: score,
                note: note,
                in: household,
                context: context
            )
        }
    }
}
