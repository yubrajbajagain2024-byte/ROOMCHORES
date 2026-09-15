import SwiftUI
import SwiftData

/// Rate what a chore is *worth*, anonymously.
///
/// The proposer's own numbers are hidden by default. Seeing "they said 4/5" first would
/// anchor almost everyone to 4, which would make the whole averaging exercise pointless.
struct ChoreValueRatingView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let chore: Chore
    let household: Household
    let rater: Roommate

    @State private var difficulty = 3
    @State private var labor = 3
    @State private var minutes = 15
    @State private var showProposal = false

    private var values: ChoreValues {
        ChoreValues(difficulty: Double(difficulty), labor: Double(labor), minutes: Double(minutes))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(chore.title).font(.title3.weight(.semibold))
                        if !chore.notes.isEmpty {
                            Text(chore.notes).font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 8) {
                            CategoryChip(category: chore.category)
                            Text(chore.recurrence.label)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ScaleSlider(
                        title: "Difficulty",
                        lowLabel: "Mindless",
                        highLabel: "Fiddly or grim",
                        symbol: "brain.head.profile",
                        tint: Theme.violet,
                        value: $difficulty
                    )
                    .padding(.vertical, 4)

                    ScaleSlider(
                        title: "Physical effort",
                        lowLabel: "Barely move",
                        highLabel: "Hauling and scrubbing",
                        symbol: "figure.strengthtraining.functional",
                        tint: Theme.teal,
                        value: $labor
                    )
                    .padding(.vertical, 4)

                    MinutesSlider(title: "How long it really takes", minutes: $minutes)
                    .padding(.vertical, 4)
                } header: {
                    Text("Your honest read")
                } footer: {
                    Text("Nobody sees which numbers were yours. The chore ends up worth the household average, so an unpopular job drifts up on its own.")
                }

                Section {
                    PointsPreview(values: values, points: PointsEngine.points(for: values))
                } header: {
                    Text("That would make it")
                }

                Section {
                    DisclosureGroup(isExpanded: $showProposal) {
                        HStack {
                            Text("They proposed")
                            Spacer()
                            PointsBadge(points: Double(chore.proposedPoints), tint: Theme.slate)
                        }
                        .padding(.vertical, 2)
                    } label: {
                        Label("Show what was proposed", systemImage: "eye")
                            .font(.subheadline)
                    }
                } footer: {
                    Text("Hidden on purpose — seeing someone else's number first tends to drag everyone towards it.")
                }
            }
            .navigationTitle("Rate the value")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Later") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        HouseholdActions.submitValueVote(
                            for: chore,
                            by: rater,
                            difficulty: difficulty,
                            labor: labor,
                            minutes: minutes,
                            context: context
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Start from the proposer's time estimate so the slider is not miles off,
                // but leave the two judgement scales at neutral.
                minutes = chore.proposedMinutes
            }
        }
    }
}
