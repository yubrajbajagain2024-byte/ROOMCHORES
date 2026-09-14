import SwiftUI
import SwiftData

struct RoommateSetupView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var household: Household

    @State private var newName = ""
    @State private var newEmoji = "🙂"
    @State private var showingEmojiPicker = false
    @FocusState private var nameFocused: Bool

    private var members: [Roommate] { household.sortedMembers }
    private var canContinue: Bool { members.count >= 2 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                SetupProgress(step: 2, total: 3)
                    .padding(.horizontal, -16)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Who lives here?")
                        .font(.largeTitle.weight(.bold))
                    Text("Add everyone who shares the chores. You'll pass the phone around, so each person needs their own name on the list.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Add form
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Button { showingEmojiPicker = true } label: {
                            ZStack {
                                Circle().fill(Theme.memberColor(members.count).gradient)
                                Text(newEmoji).font(.system(size: 24))
                            }
                            .frame(width: 50, height: 50)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose an emoji")

                        TextField("Name", text: $newName)
                            .textFieldStyle(.plain)
                            .font(.body)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(addRoommate)

                        Button(action: addRoommate) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                        }
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .card()

                if members.isEmpty {
                    EmptyStateView(
                        symbol: "person.2",
                        title: "No one added yet",
                        message: "ChoreSplit needs at least two people — anonymous ratings don't mean much on your own."
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(members) { member in
                            RoommateRow(member: member, household: household) {
                                delete(member)
                            }
                        }
                    }
                }

                Spacer(minLength: 20)

                VStack(spacing: 10) {
                    Button {
                        startChoreBuilding()
                    } label: {
                        Text("Next: add chores together")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!canContinue)

                    if !canContinue {
                        Text("Add at least two roommates to continue.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Back") {
                    household.setupStage = .household
                    try? context.save()
                }
            }
        }
        .sheet(isPresented: $showingEmojiPicker) {
            EmojiPickerView(selection: $newEmoji)
                .presentationDetents([.medium])
        }
    }

    private func addRoommate() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        let member = Roommate(name: trimmed, emoji: newEmoji, paletteIndex: members.count)
        member.household = household
        context.insert(member)
        try? context.save()

        newName = ""
        newEmoji = EmojiPickerView.suggestions.randomElement() ?? "🙂"
        nameFocused = true
    }

    private func delete(_ member: Roommate) {
        if appState.activeRoommateID == member.id { appState.activeRoommateID = nil }
        context.delete(member)
        try? context.save()
    }

    private func startChoreBuilding() {
        household.setupStage = .choreBuilding
        // The first person on the list takes the first turn.
        appState.activeRoommateID = members.first?.id
        try? context.save()
    }
}

private struct RoommateRow: View {
    let member: Roommate
    @Bindable var household: Household
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(roommate: member, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.body.weight(.medium))
                Text(shareDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Someone away half the month shouldn't be judged against a full share.
            Menu {
                Picker("Share", selection: Binding(
                    get: { member.shareWeight },
                    set: { member.shareWeight = $0 }
                )) {
                    Text("Full share").tag(1.0)
                    Text("Three quarters").tag(0.75)
                    Text("Half share").tag(0.5)
                    Text("Quarter share").tag(0.25)
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(Theme.rose.opacity(0.8))
            }
            .buttonStyle(.plain)
        }
        .card(padding: 12)
    }

    private var shareDescription: String {
        member.shareWeight == 1.0
            ? "Full share of the chores"
            : "\(Int(member.shareWeight * 100))% share — away part of the time"
    }
}

struct EmojiPickerView: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss

    static let suggestions = [
        "🙂", "😎", "🦊", "🐼", "🐙", "🦉", "🐝", "🦔",
        "🌵", "🍄", "🌻", "🪴", "⭐️", "🔥", "🌊", "🍋",
        "🎧", "🎸", "📚", "☕️", "🧃", "🍕", "🚲", "🧦"
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(Self.suggestions, id: \.self) { emoji in
                        Button {
                            selection = emoji
                            dismiss()
                        } label: {
                            Text(emoji)
                                .font(.system(size: 30))
                                .frame(width: 46, height: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(selection == emoji
                                              ? Theme.indigo.opacity(0.18)
                                              : Color(.secondarySystemGroupedBackground))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Pick an emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
