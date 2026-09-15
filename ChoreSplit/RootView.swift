import SwiftUI
import SwiftData

/// Chooses between the demo, the "connect Supabase" screen, and the real signed-in app.
struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            #if DEBUG
            if SharedPreview.isRequested {
                SharedPreviewRoot()
            } else if appState.isDemoMode {
                LocalRootView()
            } else if let client = Backend.client {
                AccountRootView(client: client)
            } else {
                BackendSetupView()
            }
            #else
            if appState.isDemoMode {
                LocalRootView()
            } else if let client = Backend.client {
                AccountRootView(client: client)
            } else {
                BackendSetupView()
            }
            #endif
        }
        .onOpenURL(perform: handle)
    }

    private func handle(_ url: URL) {
        guard url.scheme == "choresplit" else { return }
        switch url.host {
        case "login-callback":
            Backend.client?.auth.handle(url)
        case "join":
            let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "code" }?.value
            if let code, !code.isEmpty { appState.pendingInviteCode = code }
        default:
            break
        }
    }
}

/// Signed out → welcome. New account → profile. Signed in → your group, or your groups.
struct AccountRootView: View {
    @Environment(AppState.self) private var appState
    @State private var auth: AuthStore
    @State private var groups: GroupStore
    @State private var joinRequest: JoinRequest?

    init(client: SupabaseClientType) {
        _auth = State(initialValue: AuthStore(client: client))
        _groups = State(initialValue: GroupStore(client: client))
    }

    var body: some View {
        Group {
            switch auth.state {
            case .loading:
                SplashView()
            case .signedOut:
                WelcomeView()
            case .needsProfile(_, let suggestedName):
                ProfileSetupView(suggestedName: suggestedName)
            case .signedIn(let profile):
                if let groupID = groups.selectedGroupID {
                    SharedGroupRoot(groupID: groupID, userID: profile.id)
                        .id(groupID)
                } else {
                    GroupsView()
                }
            }
        }
        .environment(auth)
        .environment(groups)
        .task { auth.start() }
        .onChange(of: auth.state) { _, state in
            if case .signedIn(let profile) = state {
                appState.activeRoommateID = profile.id
                Task { await groups.load(for: profile.id) }
            }
        }
        .onChange(of: appState.pendingInviteCode) { _, code in
            // Inside a group, an invite link opens the join sheet on top; the groups screen
            // handles it itself.
            guard let code, case .signedIn = auth.state, groups.selectedGroupID != nil else { return }
            appState.pendingInviteCode = nil
            joinRequest = JoinRequest(code: code)
        }
        .sheet(item: $joinRequest) { request in
            JoinGroupView(initialCode: request.code)
                .environment(auth)
                .environment(groups)
        }
    }
}


/// The on-device demo household: no account, nothing leaves the phone. Debug builds only.
struct LocalRootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    @Query(filter: #Predicate<Household> { !$0.isShared }) private var households: [Household]

    var body: some View {
        Group {
            if let household = households.first {
                if household.setupStage == .running {
                    HomeView(household: household)
                } else {
                    OnboardingFlow(household: household)
                }
            } else {
                // Nothing exists on first launch. The household is created from a task
                // rather than inline in the body — inserting into the context while SwiftUI
                // is evaluating a body mutates state mid-update.
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
            }
        }
        .task { bootstrap() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let household = households.first,
                  household.setupStage == .running else { return }
            HouseholdActions.runMaintenance(for: household, context: context)
        }
    }

    private func bootstrap() {
        let household: Household
        if let existing = households.first {
            household = existing
        } else {
            household = Household()
            context.insert(household)
            try? context.save()
        }

        #if DEBUG
        // `--demo` loads a populated household straight away, so the running app can be
        // exercised without tapping through setup every time.
        if ProcessInfo.processInfo.arguments.contains("--demo"), household.setupStage != .running {
            DemoData.populate(household, context: context)
        }
        #endif
    }
}
