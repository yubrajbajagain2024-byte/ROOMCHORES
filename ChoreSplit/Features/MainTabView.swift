import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    let household: Household

    var body: some View {
        @Bindable var state = appState

        TabView(selection: $state.selectedTab) {
            TodayView(household: household)
                .tabItem { Label("Today", systemImage: "checklist") }
                .tag(AppTab.today)

            ChoreLibraryView(household: household)
                .tabItem { Label("Chores", systemImage: "square.grid.2x2") }
                .tag(AppTab.chores)

            RatingInboxView(household: household)
                .tabItem { Label("Rate", systemImage: "hand.thumbsup") }
                .badge(pendingRatingCount)
                .tag(AppTab.rate)

            StandingsView(household: household)
                .tabItem { Label("Standings", systemImage: "chart.bar") }
                .tag(AppTab.standings)

            SettingsView(household: household)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .task {
            HouseholdActions.runMaintenance(for: household, context: context)
            // Skipped in demo mode so the permission alert does not sit over the UI
            // while the app is being driven for screenshots.
            if !ProcessInfo.processInfo.arguments.contains("--demo") {
                await NotificationService.shared.requestAuthorization()
            }
        }
    }

    /// Badge on the Rate tab: work waiting on this person's anonymous verdict.
    private var pendingRatingCount: Int {
        guard let me = appState.activeRoommate(in: household) else { return 0 }
        let quality = (household.assignments ?? []).filter {
            $0.status == .awaitingReview && $0.assignee?.id != me.id && !$0.hasRated(me)
        }.count
        let values = household.activeChores.filter {
            $0.proposerID != me.id && !$0.hasVoted(me)
        }.count
        return quality + values
    }
}

/// The "you are currently…" control. Because a household shares one device, every
/// anonymous action depends on this being correct, so it is always visible rather than
/// buried in settings.
struct ActiveUserButton: ToolbarContent {
    let household: Household
    @Binding var showingSwitcher: Bool
    let activeMember: Roommate?

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingSwitcher = true
            } label: {
                if let activeMember {
                    HStack(spacing: 6) {
                        AvatarView(roommate: activeMember, size: 28)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "person.crop.circle")
                }
            }
            .accessibilityLabel("Switch roommate. Currently \(activeMember?.name ?? "nobody")")
        }
    }
}

struct UserSwitcherSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let household: Household

    var body: some View {
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
                                    Text(standingText(for: member))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if member.id == appState.activeRoommateID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Theme.indigo)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Who's holding the phone?")
                } footer: {
                    Text("Ratings you submit are stored without your name attached — but the app has to know who you are to stop you rating the same chore twice.")
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

    private func standingText(for member: Roommate) -> String {
        guard let standing = FairnessEngine.standings(for: household).first(where: { $0.roommate.id == member.id })
        else { return "" }
        let load = Int(standing.load.rounded())
        let target = Int(standing.target.rounded())
        return "\(load) of \(target) points this cycle"
    }
}
