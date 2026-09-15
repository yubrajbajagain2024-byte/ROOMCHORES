import SwiftUI
import SwiftData

/// "Who's holding the phone?" The household shares one device, and every anonymous rating
/// depends on this being right.
struct UserSwitcherSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let household: Household

    var body: some View {
        let scores = Dictionary(uniqueKeysWithValues: Scores.board(for: household).map { ($0.roommate.id, $0.thisCycle) })

        NavigationStack {
            List {
                Section {
                    ForEach(household.sortedMembers) { member in
                        Button {
                            appState.activeRoommateID = member.id
                            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                AvatarView(roommate: member, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name).foregroundStyle(.primary)
                                    Text("\(PointsEngine.format(scores[member.id] ?? 0)) pts earned \(household.cycleLengthDays == 7 ? "this week" : "this cycle")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if member.id == appState.activeRoommate(in: household)?.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.brand)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Who's holding the phone?")
                } footer: {
                    Text("Ratings are stored without your name — but the app has to know who you are to stop you rating the same task twice, or rating your own.")
                }
            }
            .navigationTitle("Switch roommate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
