import Foundation
import Observation
import Supabase

/// The groups you belong to, and joining, creating and leaving them.
@Observable
final class GroupStore {

    struct Summary: Identifiable, Equatable {
        let id: UUID
        let name: String
        let inviteCode: String
        let memberCount: Int
        let isOwner: Bool
        let isRunning: Bool
    }

    private(set) var groups: [Summary] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    private(set) var isWorking = false
    var errorMessage: String?

    /// The group this phone is showing. Remembered per account.
    var selectedGroupID: UUID? {
        didSet { persistSelection() }
    }

    @ObservationIgnored private let client: SupabaseClient
    @ObservationIgnored private var userID: UUID?

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Loading

    @MainActor
    func load(for userID: UUID) async {
        if self.userID != userID {
            self.userID = userID
            selectedGroupID = UserDefaults.standard.string(forKey: selectionKey(userID)).flatMap(UUID.init)
        }
        isLoading = true
        defer { isLoading = false; hasLoaded = true }
        do {
            // Row-level security returns only groups you're a member of.
            async let groupRows: [GroupRow] = client.from("groups").select().order("created_at").execute().value
            async let memberRows: [MemberRow] = client.from("group_members").select().execute().value
            let (fetchedGroups, members) = try await (groupRows, memberRows)

            groups = fetchedGroups.map { group in
                let groupMembers = members.filter { $0.groupId == group.id }
                return Summary(
                    id: group.id,
                    name: group.name,
                    inviteCode: group.inviteCode,
                    memberCount: groupMembers.count,
                    isOwner: groupMembers.contains { $0.userId == userID && $0.role == "owner" },
                    isRunning: group.setupStage == "running"
                )
            }
            // Forget a selection for a group you're no longer in.
            if let selected = selectedGroupID, !groups.contains(where: { $0.id == selected }) {
                selectedGroupID = nil
            }
            // One group and nothing chosen yet: just open it.
            if selectedGroupID == nil, groups.count == 1 {
                selectedGroupID = groups[0].id
            }
            errorMessage = nil
        } catch {
            errorMessage = BackendError.message(for: error)
        }
    }

    // MARK: - Changes

    @MainActor
    func create(name: String, cycleDays: Int) async -> UUID? {
        await perform {
            let group: GroupRow = try await self.client
                .rpc("create_group", params: CreateParams(groupName: name, cycleDays: cycleDays))
                .execute().value
            return group.id
        }
    }

    @MainActor
    func preview(code: String) async -> InvitePreview? {
        await perform {
            let rows: [InvitePreview] = try await self.client
                .rpc("preview_invite", params: CodeParam(code: code)).execute().value
            guard let preview = rows.first else {
                throw InviteError.notFound
            }
            return preview
        }
    }

    @MainActor
    func join(code: String) async -> UUID? {
        await perform {
            try await self.client.rpc("join_group", params: CodeParam(code: code)).execute().value
        }
    }

    @MainActor
    func regenerateInviteCode(for groupID: UUID) async -> String? {
        await perform {
            try await self.client.rpc("regenerate_invite_code", params: TargetParam(target: groupID)).execute().value
        }
    }

    @MainActor
    func leave(_ groupID: UUID) async -> Bool {
        let left: Bool? = await perform {
            try await self.client.rpc("leave_group", params: TargetParam(target: groupID)).execute()
            return true
        }
        if left == true {
            groups.removeAll { $0.id == groupID }
            if selectedGroupID == groupID { selectedGroupID = nil }
        }
        return left == true
    }

    /// Forget everything about the signed-out account.
    @MainActor
    func reset() {
        groups = []
        hasLoaded = false
        userID = nil
        selectedGroupID = nil
    }

    #if DEBUG
    /// Fills the list for the debug preview, which has no server to load from.
    @MainActor
    func seedForPreview(_ summaries: [Summary]) {
        groups = summaries
        hasLoaded = true
    }
    #endif

    // MARK: - Helpers

    @MainActor
    private func perform<T>(_ work: @escaping () async throws -> T) async -> T? {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            return try await work()
        } catch {
            errorMessage = (error as? InviteError)?.errorDescription ?? BackendError.message(for: error)
            return nil
        }
    }

    private func selectionKey(_ userID: UUID) -> String { "selected.group.\(userID.uuidString)" }

    private func persistSelection() {
        guard let userID else { return }
        UserDefaults.standard.set(selectedGroupID?.uuidString, forKey: selectionKey(userID))
    }

    /// Codes are shown as "K7P4-QX9A" but stored without the dash.
    static func formatted(_ code: String) -> String {
        let clean = code.uppercased().filter { $0.isLetter || $0.isNumber }
        guard clean.count == 8 else { return clean }
        return "\(clean.prefix(4))-\(clean.suffix(4))"
    }

    static func inviteURL(code: String) -> URL {
        URL(string: "choresplit://join?code=\(code.uppercased().filter { $0.isLetter || $0.isNumber })")!
    }
}

enum InviteError: LocalizedError {
    case notFound
    var errorDescription: String? { "That invite code doesn't match a group. Check it and try again." }
}

private struct CreateParams: Encodable {
    let groupName: String
    let cycleDays: Int
    enum CodingKeys: String, CodingKey {
        case groupName = "group_name"
        case cycleDays = "cycle_days"
    }
}

private struct CodeParam: Encodable { let code: String }
private struct TargetParam: Encodable { let target: UUID }
