import SwiftUI
import SwiftData

/// Rate how well a finished chore was actually done. This is what stops "done" meaning
/// "shoved in a cupboard" — and it moves real points, so it is worth being honest about.
struct QualityRatingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let assignment: Assignment
    let household: Household
    let rater: Roommate

    @State private var score = 3
    @State private var note = ""

    private var payout: Double {
        PointsEngine.settledPoints(quoted: assignment.pointsQuoted, averageQuality: Double(score))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        if let assignee = assignment.assignee {
                            AvatarView(roommate: assignee, size: 44)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(assignment.title).font(.headline)
                                Text("Done by \(assignee.name)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            ForEach(1...5, id: \.self) { value in
                                Button {
                                    score = value
                                    UISelectionFeedbackGenerator().selectionChanged()
                                } label: {
                                    Image(systemName: value <= score ? "star.fill" : "star")
                                        .font(.system(size: 30))
                                        .foregroundStyle(value <= score ? Theme.amber : Color.secondary.opacity(0.4))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                            }
                        }
                        .frame(maxWidth: .infinity)

                        Text(PointsEngine.describeQuality(Double(score)))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.qualityColor(Double(score)))
                            .animation(.snappy, value: score)
                    }
                    .padding(.vertical, 6)
                } header: {
                    Text("How well was it done?")
                } footer: {
                    Text("Three stars is \u{201C}done properly\u{201D} and pays the chore's full value. Be sparing with one star — it's for work that has to be redone.")
                }

                Section {
                    HStack {
                        Text("Chore is worth")
                        Spacer()
                        Text("\(assignment.pointsQuoted) pts").foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Your rating would pay")
                        Spacer()
                        Text(String(format: "%.1f pts", payout))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.qualityColor(Double(score)))
                            .contentTransition(.numericText())
                            .animation(.snappy, value: payout)
                    }
                } header: {
                    Text("Effect on points")
                } footer: {
                    Text("The final figure is the average of everyone's ratings, not just yours.")
                }

                Section {
                    TextField("Anything worth saying? (optional)", text: $note, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Anonymous note")
                } footer: {
                    Text("Shown to them without your name. Notes are shuffled before display so the order doesn't give anyone away.")
                }
            }
            .navigationTitle("Rate the work")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        HouseholdActions.submitQualityRating(
                            for: assignment,
                            by: rater,
                            score: score,
                            note: note,
                            in: household,
                            context: context
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}
