import SwiftUI

/// Signed in, but no group open: pick one, start one, or join one.
struct GroupsView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(GroupStore.self) private var groups
    @Environment(AppState.self) private var appState

    @State private var showingCreate = false
    @State private var joinCode: JoinRequest?

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header

                if groups.groups.isEmpty {
                    emptyState
                } else {
                    groupList
                }

                actions
            }
            .padding(.bottom, 32)
        }
        .background(Theme.feedBackground)
        .refreshable {
            if let id = auth.userID { await groups.load(for: id) }
        }
        .sheet(isPresented: $showingCreate) {
            CreateGroupView()
        }
        .sheet(item: $joinCode) { request in
            JoinGroupView(initialCode: request.code)
        }
        .onAppear(perform: openPendingInvite)
        .onChange(of: appState.pendingInviteCode) { _, _ in openPendingInvite() }
    }

    private var header: some View {
        HStack {
            Wordmark(size: 30)
            Spacer()
            Menu {
                if case .signedIn(let profile) = auth.state {
                    Text("Signed in as \(profile.displayName)")
                }
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
            } label: {
                ZStack {
                    Circle().fill(Theme.chipFill)
                    if case .signedIn(let profile) = auth.state {
                        Text(profile.emoji).font(.system(size: 20))
                    } else {
                        Image(systemName: "person.fill")
                    }
                }
                .frame(width: 38, height: 38)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.feedCard)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "house.and.flag.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.brand)
            Text("You're not in a group yet")
                .font(.system(size: 20, weight: .bold))
            Text("Start one for your place and invite your roommates, or join theirs with the invite code they sent you.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 36)
        .frame(maxWidth: .infinity)
        .background(Theme.feedCard)
    }

    private var groupList: some View {
        VStack(alignment: .leading, spacing: 0) {
            FeedSectionHeader(title: "Your groups")
                .padding(.bottom, 8)
            ForEach(Array(groups.groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Rectangle().fill(Theme.hairline).frame(height: 0.5).padding(.leading, 70)
                }
                Button {
                    groups.selectedGroupID = group.id
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.brand.opacity(0.12))
                            Image(systemName: "house.fill").foregroundStyle(Theme.brand)
                        }
                        .frame(width: 44, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                            Text("\(group.memberCount) member\(group.memberCount == 1 ? "" : "s")\(group.isOwner ? " · Owner" : "")\(group.isRunning ? "" : " · Setting up")")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            PrimaryButton(title: "Create a group", systemImage: "plus") {
                showingCreate = true
            }
            SecondaryButton(title: "Join with an invite code") {
                joinCode = JoinRequest(code: "")
            } icon: {
                Image(systemName: "ticket.fill").foregroundStyle(Theme.brand)
            }
            if groups.isLoading && !groups.hasLoaded {
                ProgressView().padding(.top, 8)
            }
            ErrorText(message: groups.errorMessage)
        }
        .padding(16)
        .background(Theme.feedCard)
    }

    private func openPendingInvite() {
        guard let code = appState.pendingInviteCode else { return }
        appState.pendingInviteCode = nil
        joinCode = JoinRequest(code: code)
    }
}

struct JoinRequest: Identifiable {
    let id = UUID()
    let code: String
}

// MARK: - Create

struct CreateGroupView: View {
    @Environment(GroupStore.self) private var groups
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var cycleDays = 7
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Name your group")
                    .font(.system(size: 26, weight: .bold))
                Text("Usually the place you share — your roommates will see it when they join.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)

                PillField {
                    TextField("Flat 3B", text: $name)
                        .focused($focused)
                        .submitLabel(.done)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("How often does the scoreboard reset?")
                        .font(.system(size: 15, weight: .semibold))
                    Picker("Cycle", selection: $cycleDays) {
                        Text("Every 3 days").tag(3)
                        Text("Weekly").tag(7)
                        Text("Fortnightly").tag(14)
                    }
                    .pickerStyle(.segmented)
                }

                ErrorText(message: groups.errorMessage)

                PrimaryButton(title: "Create group", isWorking: groups.isWorking,
                              isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty) {
                    Task {
                        guard let id = await groups.create(name: name, cycleDays: cycleDays) else { return }
                        if let userID = auth.userID { await groups.load(for: userID) }
                        groups.selectedGroupID = id
                        dismiss()
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(Theme.feedCard.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }
}

// MARK: - Join

struct JoinGroupView: View {
    @Environment(GroupStore.self) private var groups
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let initialCode: String

    @State private var code = ""
    @State private var preview: InvitePreview?
    @FocusState private var focused: Bool

    private var cleanCode: String { code.uppercased().filter { $0.isLetter || $0.isNumber } }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Text("Join a group")
                    .font(.system(size: 26, weight: .bold))
                Text("Enter the 8-character invite code a roommate sent you.")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.secondaryText)

                PillField {
                    TextField("K7P4-QX9A", text: $code)
                        .font(.system(size: 24, weight: .semibold, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onChange(of: code) { _, value in
                            let formatted = GroupStore.formatted(value)
                            if formatted != value && cleanCode.count == 8 { code = formatted }
                            if preview != nil { preview = nil }
                        }
                }

                if let preview {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.brand.opacity(0.12))
                            Image(systemName: "house.fill").foregroundStyle(Theme.brand)
                        }
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(preview.groupName).font(.system(size: 18, weight: .bold))
                            Text("\(preview.memberCount) member\(preview.memberCount == 1 ? "" : "s")")
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chipFill))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                ErrorText(message: groups.errorMessage)

                if let preview {
                    PrimaryButton(title: preview.alreadyMember ? "Open \(preview.groupName)" : "Join \(preview.groupName)",
                                  isWorking: groups.isWorking) {
                        Task { await join(preview) }
                    }
                } else {
                    PrimaryButton(title: "Find group", isWorking: groups.isWorking, isEnabled: cleanCode.count == 8) {
                        Task {
                            let found = await groups.preview(code: cleanCode)
                            withAnimation { preview = found }
                        }
                    }
                }
                Spacer()
            }
            .padding(24)
            .background(Theme.feedCard.ignoresSafeArea())
            .animation(.snappy, value: preview)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                code = GroupStore.formatted(initialCode)
                focused = initialCode.isEmpty
                if cleanCode.count == 8 {
                    Task { preview = await groups.preview(code: cleanCode) }
                }
            }
        }
    }

    private func join(_ preview: InvitePreview) async {
        let groupID = preview.alreadyMember ? preview.groupId : await groups.join(code: cleanCode)
        guard let groupID else { return }
        if let userID = auth.userID { await groups.load(for: userID) }
        groups.selectedGroupID = groupID
        dismiss()
    }
}
