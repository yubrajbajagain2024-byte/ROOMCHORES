import SwiftUI
import SwiftData

/// Volunteering for extra work. Someone who wants to build a buffer before a busy week
/// should be able to, rather than waiting for the app to hand them something.
struct ClaimChoreSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let household: Household
    let claimant: Roommate

    private var available: [Chore] {
        FairnessEngine.availableChores(in: household).sorted { $0.points > $1.points }
    }

    private var standing: MemberStanding? {
        FairnessEngine.standings(for: household).first { $0.roommate.id == claimant.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if available.isEmpty {
                    EmptyStateView(
                        symbol: "tray",
                        title: "Nothing left to claim",
                        message: "Every chore in the library is already on someone's list."
                    )
                } else {
                    List {
                        if let standing {
                            Section {
                                HStack {
                                    Text(standing.deficit > 0
                                         ? "You're \(Int(standing.deficit.rounded())) points short"
                                         : "You're already at your share")
                                        .font(.subheadline)
                                    Spacer()
                                    PointsBadge(points: standing.load, size: .small)
                                }
                            }
                        }

                        Section {
                            ForEach(available) { chore in
                                Button {
                                    claim(chore)
                                } label: {
                                    ChoreSummaryRow(chore: chore, household: household)
                                }
                                .buttonStyle(.plain)
                            }
                        } header: {
                            Text("Up for grabs")
                        } footer: {
                            Text("Claiming a chore counts towards your share straight away, and the points settle once your housemates have rated the work.")
                        }
                    }
                }
            }
            .navigationTitle("Claim a chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func claim(_ chore: Chore) {
        HouseholdActions.assign(
            chore: chore,
            to: claimant,
            due: FairnessEngine.defaultDueDate(for: chore, in: household),
            in: household,
            context: context,
            autoAssigned: false,
            reason: "Claimed by \(claimant.shortName)"
        )
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}
