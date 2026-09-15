import Foundation
import Supabase

/// Everything the sync engine needs from the server. Supabase is the real implementation;
/// tests use an in-memory one, so the sync rules can be checked without a network.
protocol RemoteStore: AnyObject, Sendable {
    func fetchSnapshot(groupID: UUID) async throws -> GroupSnapshot
    func saveChore(_ row: ChoreRow) async throws
    func saveAssignment(_ row: AssignmentRow) async throws
    func castValueVote(choreID: UUID, difficulty: Int, labor: Int, minutes: Int) async throws
    func rateAssignment(id: UUID, score: Int, note: String) async throws
    func updateMember(groupID: UUID, userID: UUID, shareWeight: Double, carryOverPoints: Double) async throws
    func updateGroup(_ update: GroupUpdate) async throws
    func settleDueAssignments(groupID: UUID) async throws
    func claimMaintenance(groupID: UUID) async throws -> Bool
    func uploadProofVideo(fileURL: URL, path: String) async throws
    func deleteProofVideo(path: String) async throws
    func playableVideoURL(path: String) async throws -> URL
    /// Fires whenever another phone changes something in the group.
    func changes(groupID: UUID) -> AsyncStream<Void>
}

final class SupabaseRemoteStore: RemoteStore, @unchecked Sendable {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    // MARK: - Reading

    func fetchSnapshot(groupID: UUID) async throws -> GroupSnapshot {
        async let groups: [GroupRow] = client.from("groups").select().eq("id", value: groupID).execute().value
        async let members: [MemberRow] = client.from("group_members").select().eq("group_id", value: groupID).execute().value
        // Row-level security already limits this to you and people you share a group with.
        async let profiles: [ProfileRow] = client.from("profiles").select("id,display_name,emoji").execute().value
        async let chores: [ChoreRow] = client.from("chores").select().eq("group_id", value: groupID).execute().value
        async let valueSummaries: [ValueSummaryRow] = client
            .rpc("chore_value_summaries", params: GroupParam(targetGroup: groupID)).execute().value
        async let myVotes: [MyVoteRow] = client.from("chore_value_votes")
            .select("chore_id,difficulty,labor,minutes").eq("group_id", value: groupID).execute().value
        async let assignments: [AssignmentRow] = client.from("assignments").select().eq("group_id", value: groupID).execute().value
        async let ratingSummaries: [RatingSummaryRow] = client
            .rpc("assignment_rating_summaries", params: GroupParam(targetGroup: groupID)).execute().value
        async let myRatings: [MyRatingRow] = client.from("quality_ratings")
            .select("assignment_id,score,note").eq("group_id", value: groupID).execute().value

        guard let group = try await groups.first else {
            throw RemoteStoreError.groupUnavailable
        }
        let memberRows = try await members
        let memberIDs = Set(memberRows.map(\.userId))

        return GroupSnapshot(
            group: group,
            members: memberRows,
            profiles: try await profiles.filter { memberIDs.contains($0.id) },
            chores: try await chores,
            valueSummaries: try await valueSummaries,
            myVotes: try await myVotes,
            assignments: try await assignments,
            ratingSummaries: try await ratingSummaries,
            myRatings: try await myRatings
        )
    }

    // MARK: - Writing

    /// Update if the chore exists, insert if it doesn't. A plain upsert would fail when you edit
    /// someone else's chore, because the insert rule insists the proposer is you.
    func saveChore(_ row: ChoreRow) async throws {
        let updated: [IDRow] = try await client.from("chores")
            .update(row.editableFields).eq("id", value: row.id)
            .select("id").execute().value
        if updated.isEmpty {
            try await client.from("chores").insert(row, returning: .minimal).execute()
        }
    }

    func saveAssignment(_ row: AssignmentRow) async throws {
        let updated: [IDRow] = try await client.from("assignments")
            .update(row).eq("id", value: row.id)
            .select("id").execute().value
        if updated.isEmpty {
            try await client.from("assignments").insert(row, returning: .minimal).execute()
        }
    }

    func castValueVote(choreID: UUID, difficulty: Int, labor: Int, minutes: Int) async throws {
        try await client.rpc("cast_value_vote", params: VoteParams(
            targetChore: choreID, difficulty: difficulty, labor: labor, minutes: minutes
        )).execute()
    }

    func rateAssignment(id: UUID, score: Int, note: String) async throws {
        try await client.rpc("rate_assignment", params: RateParams(target: id, score: score, note: note)).execute()
    }

    func updateMember(groupID: UUID, userID: UUID, shareWeight: Double, carryOverPoints: Double) async throws {
        try await client.from("group_members")
            .update(MemberEdit(shareWeight: shareWeight, carryOverPoints: carryOverPoints))
            .eq("group_id", value: groupID).eq("user_id", value: userID)
            .execute()
    }

    func updateGroup(_ update: GroupUpdate) async throws {
        try await client.from("groups").update(update.editableFields).eq("id", value: update.id).execute()
    }

    func settleDueAssignments(groupID: UUID) async throws {
        try await client.rpc("settle_due_assignments", params: GroupParam(targetGroup: groupID)).execute()
    }

    func claimMaintenance(groupID: UUID) async throws -> Bool {
        try await client.rpc("claim_maintenance", params: GroupParam(targetGroup: groupID)).execute().value
    }

    // MARK: - Videos

    func uploadProofVideo(fileURL: URL, path: String) async throws {
        _ = try await client.storage.from(Backend.proofVideoBucket).upload(
            path,
            fileURL: fileURL,
            options: FileOptions(contentType: "video/mp4", upsert: true)
        )
    }

    func deleteProofVideo(path: String) async throws {
        _ = try await client.storage.from(Backend.proofVideoBucket).remove(paths: [path])
    }

    func playableVideoURL(path: String) async throws -> URL {
        try await client.storage.from(Backend.proofVideoBucket).createSignedURL(path: path, expiresIn: 3600)
    }

    // MARK: - Live changes

    func changes(groupID: UUID) -> AsyncStream<Void> {
        let channel = client.channel("group-\(groupID.uuidString.lowercased())")
        let streams = [
            channel.postgresChange(AnyAction.self, table: "groups", filter: .eq("id", value: groupID)),
            channel.postgresChange(AnyAction.self, table: "group_members", filter: .eq("group_id", value: groupID)),
            channel.postgresChange(AnyAction.self, table: "chores", filter: .eq("group_id", value: groupID)),
            channel.postgresChange(AnyAction.self, table: "assignments", filter: .eq("group_id", value: groupID))
        ]

        return AsyncStream { continuation in
            let listeners = streams.map { stream in
                Task {
                    for await _ in stream { continuation.yield() }
                }
            }
            let subscription = Task {
                try? await channel.subscribeWithError()
            }
            continuation.onTermination = { [client] _ in
                listeners.forEach { $0.cancel() }
                subscription.cancel()
                Task { await client.removeChannel(channel) }
            }
        }
    }
}

enum RemoteStoreError: LocalizedError {
    case groupUnavailable

    var errorDescription: String? {
        switch self {
        case .groupUnavailable: return "This group isn't available any more — you may have left it."
        }
    }
}

private struct IDRow: Decodable { let id: UUID }

private struct GroupParam: Encodable {
    let targetGroup: UUID
    enum CodingKeys: String, CodingKey { case targetGroup = "target_group" }
}

private struct VoteParams: Encodable {
    let targetChore: UUID
    let difficulty: Int
    let labor: Int
    let minutes: Int
    enum CodingKeys: String, CodingKey {
        case difficulty, labor, minutes
        case targetChore = "target_chore"
    }
}

private struct RateParams: Encodable {
    let target: UUID
    let score: Int
    let note: String
}

private struct MemberEdit: Encodable {
    let shareWeight: Double
    let carryOverPoints: Double
    enum CodingKeys: String, CodingKey {
        case shareWeight = "share_weight"
        case carryOverPoints = "carry_over_points"
    }
}
