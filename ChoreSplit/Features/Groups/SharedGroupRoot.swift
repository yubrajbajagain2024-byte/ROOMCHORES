import SwiftUI
import SwiftData

/// Opens one shared group: starts syncing it, then shows setup or the feed.
struct SharedGroupRoot: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState
    @Environment(GroupStore.self) private var groups

    let groupID: UUID
    let userID: UUID

    @Query private var households: [Household]
    @State private var engine: SyncEngine?

    init(groupID: UUID, userID: UUID) {
        self.groupID = groupID
        self.userID = userID
        _households = Query(filter: #Predicate<Household> { $0.id == groupID })
    }

    var body: some View {
        Group {
            if let engine, engine.groupUnavailable {
                unavailable
            } else if let engine, let household = households.first {
                Group {
                    if household.setupStage == .running {
                        HomeView(household: household)
                    } else {
                        GroupSetupView(household: household)
                    }
                }
                .environment(engine)
            } else {
                loading
            }
        }
        .task(id: groupID) {
            let engine = SyncEngine(
                groupID: groupID,
                currentUserID: userID,
                remote: SupabaseRemoteStore(client: Backend.client!),
                context: context
            )
            self.engine = engine
            HouseholdActions.sync = engine
            appState.activeRoommateID = userID

            await engine.refresh()
            engine.startLive()
            await engine.maintain()

            // A slow heartbeat on top of live updates, for anything realtime missed.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(120))
                guard !Task.isCancelled else { break }
                await engine.maintain()
            }
        }
        .onDisappear {
            engine?.stop()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let engine else { return }
            Task { await engine.maintain() }
        }
    }

    private var loading: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(engine?.lastError ?? "Loading your group…")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
            if engine?.lastError != nil {
                Button("Try again") {
                    Task { await engine?.refresh() }
                }
                .tint(Theme.brand)
                Button("Back to my groups") { groups.selectedGroupID = nil }
                    .tint(Theme.secondaryText)
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.feedBackground)
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 40))
                .foregroundStyle(Theme.secondaryText)
            Text("You're not in this group any more")
                .font(.system(size: 19, weight: .bold))
            Text("You may have left, or the group was deleted.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
            PrimaryButton(title: "Back to my groups") {
                AccountSession.forgetGroup(groupID, context: context)
                groups.selectedGroupID = nil
            }
            .padding(.top, 8)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.feedBackground)
    }
}
