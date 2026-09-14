import SwiftUI
import SwiftData

/// Decides whether the household is still being set up or is in day-to-day use.
struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState

    @Query private var households: [Household]

    var body: some View {
        Group {
            if let household = households.first {
                if household.setupStage == .running {
                    MainTabView(household: household)
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
