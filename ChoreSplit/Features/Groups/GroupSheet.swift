import SwiftUI
import SwiftData

/// The group menu: who's in, inviting more, switching groups, and your account.
struct GroupSheet: View {
    @Environment(AuthStore.self) private var auth
    @Environment(GroupStore.self) private var groups
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let household: Household

    @State private var showingInvite = false
    @State private var confirmingLeave = false
    @State private var confirmingSignOut = false

    var body: some View {
        let scores = Dictionary(uniqueKeysWithValues: Scores.board(for: household).map { ($0.roommate.id, $0.thisCycle) })

        NavigationStack {
            List {
                Section {
                    ForEach(household.sortedMembers) { member in
                        HStack(spacing: 12) {
                            AvatarView(roommate: member, size: 38)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.id == sync.currentUserID ? "\(member.name) (you)" : member.name)
                                Text("\(PointsEngine.format(scores[member.id] ?? 0)) pts this \(household.cycleLengthDays == 7 ? "week" : "cycle")\(member.isOwner ? " · Owner" : "")")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    Button {
                        showingInvite = true
                    } label: {
                        Label("Invite friends", systemImage: "person.badge.plus")
                    }
                } header: {
                    Text(household.name)
                }

                Section {
                    Button {
                        groups.selectedGroupID = nil
                        dismiss()
                    } label: {
                        Label("Switch group", systemImage: "arrow.left.arrow.right")
                    }
                    Button(role: .destructive) {
                        confirmingLeave = true
                    } label: {
                        Label("Leave \(household.name)", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section {
                    if case .signedIn(let profile) = auth.state {
                        LabeledContent("Signed in as") {
                            Text("\(profile.emoji) \(profile.displayName)")
                        }
                    }
                    Button(role: .destructive) {
                        confirmingSignOut = true
                    } label: {
                        Label("Sign out", systemImage: "power")
                    }
                } footer: {
                    Text(syncStatus)
                }
            }
            .navigationTitle("Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingInvite) {
                InviteFriendsView(household: household)
            }
            .confirmationDialog("Leave \(household.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave group", role: .destructive) {
                    Task {
                        if await groups.leave(household.id) {
                            AccountSession.forgetGroup(household.id, context: context)
                            dismiss()
                        }
                    }
                }
            } message: {
                Text(household.sortedMembers.count == 1
                     ? "You're the only member, so the group and its history will be deleted."
                     : "Your finished tasks stay in everyone's history. You can rejoin with an invite code.")
            }
            .confirmationDialog("Sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task {
                        await sync.flush()
                        await auth.signOut()
                        groups.reset()
                        AccountSession.forgetAllSharedData(context: context)
                    }
                }
            } message: {
                Text(sync.pendingCount > 0
                     ? "\(sync.pendingCount) change\(sync.pendingCount == 1 ? " hasn't" : "s haven't") synced yet and will be lost."
                     : "Your groups stay on the server; sign back in any time.")
            }
        }
    }

    private var syncStatus: String {
        if let error = sync.lastError { return error }
        if sync.pendingCount > 0 { return "\(sync.pendingCount) change\(sync.pendingCount == 1 ? "" : "s") waiting to sync." }
        if let synced = household.lastSyncedAt {
            return "Synced \(synced.formatted(.relative(presentation: .named)))."
        }
        return ""
    }
}

/// Clearing local copies when someone leaves a group or signs out, so the next account on this
/// phone never sees another person's household.
enum AccountSession {
    static func forgetGroup(_ groupID: UUID, context: ModelContext) {
        if let household = try? context.fetch(FetchDescriptor<Household>(predicate: #Predicate { $0.id == groupID })).first {
            context.delete(household)
        }
        for pending in (try? context.fetch(FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.groupID == groupID }))) ?? [] {
            context.delete(pending)
        }
        try? context.save()
    }

    static func forgetAllSharedData(context: ModelContext) {
        for household in (try? context.fetch(FetchDescriptor<Household>(predicate: #Predicate { $0.isShared }))) ?? [] {
            context.delete(household)
        }
        try? context.delete(model: PendingOperation.self)
        try? context.save()
        HouseholdActions.sync = nil
    }
}
