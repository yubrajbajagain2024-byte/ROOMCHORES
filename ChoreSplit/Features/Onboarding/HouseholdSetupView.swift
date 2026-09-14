import SwiftUI
import SwiftData

struct HouseholdSetupView: View {
    @Environment(\.modelContext) private var context
    @Bindable var household: Household
    @FocusState private var nameFocused: Bool

    private let cycleOptions = [3, 7, 14]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SetupProgress(step: 1, total: 3)
                    .padding(.horizontal, -16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Set up your household")
                        .font(.largeTitle.weight(.bold))
                    Text("ChoreSplit keeps score in points rather than chore counts, so three bin runs never quietly equal one deep-cleaned bathroom.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("What do you call the place?")
                        .font(.subheadline.weight(.semibold))
                    TextField("Flat 3B", text: $household.name)
                        .textFieldStyle(.plain)
                        .font(.title3)
                        .focused($nameFocused)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("How often does the scoreboard reset?")
                        .font(.subheadline.weight(.semibold))

                    Picker("Cycle length", selection: $household.cycleLengthDays) {
                        ForEach(cycleOptions, id: \.self) { days in
                            Text(label(for: days)).tag(days)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(explanation(for: household.cycleLengthDays))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .card()

                Spacer(minLength: 20)

                Button {
                    household.setupStage = .roommates
                    try? context.save()
                } label: {
                    Text("Add roommates")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(household.name.trimmingCharacters(in: .whitespaces).isEmpty)

                #if DEBUG
                Button("Fill with a demo household") {
                    DemoData.populate(household, context: context)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
                #endif
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .onAppear { nameFocused = household.name.isEmpty }
    }

    private func label(for days: Int) -> String {
        switch days {
        case 3:  return "Every 3 days"
        case 7:  return "Weekly"
        default: return "Fortnightly"
        }
    }

    private func explanation(for days: Int) -> String {
        switch days {
        case 3:  return "Tight loop. Imbalances get corrected fast, but expect the app to reshuffle chores often."
        case 7:  return "The usual choice. Fair shares are judged across the week, so one busy day doesn't count against you."
        default: return "Relaxed. Good if people travel, but someone can coast for a while before it shows."
        }
    }
}
