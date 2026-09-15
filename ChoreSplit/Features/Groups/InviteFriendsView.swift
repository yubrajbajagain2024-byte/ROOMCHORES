import SwiftUI

/// The invite code, ready to share, and who's already in.
struct InviteFriendsView: View {
    @Environment(GroupStore.self) private var groups
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss

    let household: Household

    @State private var copied = false
    @State private var confirmingNewCode = false

    private var me: Roommate? { household.sortedMembers.first { $0.id == sync.currentUserID } }
    private var code: String { GroupStore.formatted(household.inviteCode) }
    private var shareMessage: String {
        "Join \(household.name) on ChoreSplit so we can split the chores fairly. Open \(GroupStore.inviteURL(code: household.inviteCode).absoluteString) or enter the invite code \(code) in the app."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    codeCard
                    membersCard
                }
                .padding(.bottom, 24)
            }
            .background(Theme.feedBackground)
            .navigationTitle("Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog("Make a new invite code?", isPresented: $confirmingNewCode, titleVisibility: .visible) {
                Button("New code") {
                    Task {
                        if await groups.regenerateInviteCode(for: household.id) != nil {
                            await sync.pull()
                        }
                    }
                }
            } message: {
                Text("The current code stops working. Anyone already in the group stays in.")
            }
        }
    }

    private var codeCard: some View {
        VStack(spacing: 16) {
            Text("Share this code with your roommates")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)

            Text(code)
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .tracking(2)
                .textSelection(.enabled)
                .accessibilityLabel("Invite code \(code.map(String.init).joined(separator: " "))")

            HStack(spacing: 10) {
                ShareLink(item: shareMessage) {
                    Label("Share invite", systemImage: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.brand))
                }
                Button {
                    UIPasteboard.general.string = household.inviteCode
                    withAnimation { copied = true }
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        withAnimation { copied = false }
                    }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 120, height: 46)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chipFill))
                }
                .buttonStyle(.plain)
            }

            Text("They'll need ChoreSplit installed and to sign in first.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText)

            if me?.isOwner == true {
                Button("Make a new code") { confirmingNewCode = true }
                    .font(.system(size: 14, weight: .medium))
                    .tint(Theme.brand)
            }
            ErrorText(message: groups.errorMessage)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Theme.feedCard)
    }

    private var membersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedSectionHeader(title: "In the group", subtitle: "\(household.sortedMembers.count) member\(household.sortedMembers.count == 1 ? "" : "s")")
                .padding(.bottom, 8)
            ForEach(household.sortedMembers) { member in
                HStack(spacing: 12) {
                    AvatarView(roommate: member, size: 40)
                    Text(member.id == sync.currentUserID ? "\(member.name) (you)" : member.name)
                        .font(.system(size: 16))
                    Spacer()
                    if member.isOwner {
                        Text("Owner")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.brand)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.brand.opacity(0.12)))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }
}
