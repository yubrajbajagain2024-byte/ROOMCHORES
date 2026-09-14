import SwiftUI
import SwiftData

/// Setup is a shared activity, not a solo form: the household names itself, adds everyone,
/// then passes the phone around so each roommate proposes the chores they care about and
/// what they think each is worth.
struct OnboardingFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @Bindable var household: Household

    var body: some View {
        NavigationStack {
            Group {
                switch household.setupStage {
                case .household:      HouseholdSetupView(household: household)
                case .roommates:      RoommateSetupView(household: household)
                case .choreBuilding:  ChoreBuildingView(household: household)
                case .running:        EmptyView()
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
}

/// The step counter shown at the top of each setup screen.
struct SetupProgress: View {
    let step: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(index <= step ? Theme.indigo : Color(.tertiarySystemFill))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal)
        .accessibilityLabel("Step \(step) of \(total)")
    }
}
