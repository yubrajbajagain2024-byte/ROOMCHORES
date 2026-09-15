#if DEBUG
import SwiftUI
import SwiftData
import Supabase

/// The signed-in, multi-person screens with made-up data and no server — for looking at them in
/// a simulator before a Supabase project exists. Debug builds only.
///
///     --preview-shared                 the feed of a running group
///     --preview-shared --setup         a group still being set up
///     --preview-shared --invite        …with the invite sheet open
///     --preview-shared --group-menu    …with the group menu open
///     --preview-shared --signed-out    the welcome screen
///     --preview-shared --profile       the new-account profile screen
///     --preview-shared --groups        the "your groups" screen
enum SharedPreview {
    static var isRequested: Bool { has("--preview-shared") }
    static func has(_ flag: String) -> Bool { ProcessInfo.processInfo.arguments.contains(flag) }

    static let groupID = UUID(uuidString: "7E57E57E-0000-4000-8000-000000000001")!
    static let me = UUID(uuidString: "7E57E57E-0000-4000-8000-0000000000A1")!
    static let priya = UUID(uuidString: "7E57E57E-0000-4000-8000-0000000000A2")!
    static let sam = UUID(uuidString: "7E57E57E-0000-4000-8000-0000000000A3")!

    /// A client pointed nowhere. Nothing in the preview calls it unless a button that needs the
    /// server is pressed, which then just fails.
    static let offlineClient = SupabaseClient(supabaseURL: URL(string: "https://preview.supabase.co")!, supabaseKey: "preview")

    static func snapshot(running: Bool) -> GroupSnapshot {
        let now = Date()
        let hour: TimeInterval = 3600
        let chores: [(String, String, String, UUID, Int, Int, Int)] = [
            ("Scrub the toilet", "bathroom", "weekly", priya, 4, 3, 15),
            ("Take the bins out", "trash", "weekly", me, 1, 3, 10),
            ("Wash up after dinner", "kitchen", "daily", sam, 2, 2, 20),
            ("Vacuum the living room", "living", "weekly", me, 2, 3, 25),
            ("Clean out the fridge", "kitchen", "biweekly", priya, 4, 2, 30)
        ]
        let choreRows = chores.enumerated().map { index, c in
            ChoreRow(id: UUID(uuidString: "7E57E57E-0000-4000-8000-00000000C00\(index)")!, groupId: groupID, title: c.0, notes: "",
                     category: c.1, recurrence: c.2, isActive: true, proposerId: c.3, proposedDifficulty: c.4,
                     proposedLabor: c.5, proposedMinutes: c.6, createdAt: now)
        }
        func task(_ n: Int, chore: Int, to person: UUID, status: String, dueIn: TimeInterval, points: Int, awarded: Double? = nil) -> AssignmentRow {
            AssignmentRow(id: UUID(uuidString: "7E57E57E-0000-4000-8000-00000000D00\(n)")!, groupId: groupID, choreId: choreRows[chore].id,
                          assigneeId: person, assignedAt: now.addingTimeInterval(-2 * 24 * hour), dueDate: now.addingTimeInterval(dueIn),
                          status: status, pointsQuoted: points, awardedPoints: awarded,
                          completedAt: status == "open" ? nil : now.addingTimeInterval(-3 * hour),
                          wasAutoAssigned: true, assignmentReason: "", proofVideoPath: nil, proofVideoDuration: nil)
        }

        return GroupSnapshot(
            group: GroupRow(id: groupID, name: "Flat 3B", cycleLengthDays: 7, cycleStartDate: now.addingTimeInterval(-3 * 24 * hour),
                            setupStage: running ? "running" : "choreBuilding", fairnessTolerance: 0.1,
                            minimumRatingsToReveal: 2, ratingWindowHours: 48, autoAssignEnabled: true,
                            inviteCode: "K7P4QX9A", createdBy: me),
            members: [
                MemberRow(groupId: groupID, userId: me, role: "owner", shareWeight: 1, carryOverPoints: 0, paletteIndex: 0, joinedAt: now.addingTimeInterval(-9 * 24 * hour)),
                MemberRow(groupId: groupID, userId: priya, role: "member", shareWeight: 1, carryOverPoints: 0, paletteIndex: 1, joinedAt: now.addingTimeInterval(-8 * 24 * hour)),
                MemberRow(groupId: groupID, userId: sam, role: "member", shareWeight: 1, carryOverPoints: 0, paletteIndex: 2, joinedAt: now.addingTimeInterval(-8 * 24 * hour))
            ],
            profiles: [
                ProfileRow(id: me, displayName: "Alex Kerr", emoji: "🦊"),
                ProfileRow(id: priya, displayName: "Priya Shah", emoji: "🌻"),
                ProfileRow(id: sam, displayName: "Sam Okafor", emoji: "🎧")
            ],
            chores: choreRows,
            valueSummaries: choreRows.map { ValueSummaryRow(choreId: $0.id, voteCount: running ? 2 : 0, avgDifficulty: running ? 3 : nil, avgLabor: running ? 3 : nil, avgMinutes: running ? 20 : nil) },
            myVotes: running ? [] : [MyVoteRow(choreId: choreRows[0].id, difficulty: 4, labor: 3, minutes: 20)],
            assignments: running ? [
                task(1, chore: 1, to: me, status: "open", dueIn: 5 * hour, points: 2),
                task(2, chore: 3, to: me, status: "open", dueIn: 26 * hour, points: 2),
                task(3, chore: 0, to: priya, status: "awaitingReview", dueIn: -4 * hour, points: 3),
                task(4, chore: 4, to: priya, status: "settled", dueIn: -30 * hour, points: 3, awarded: 3),
                task(5, chore: 2, to: sam, status: "settled", dueIn: -50 * hour, points: 2, awarded: 1.5),
                task(6, chore: 2, to: me, status: "settled", dueIn: -26 * hour, points: 2, awarded: 2)
            ] : [],
            ratingSummaries: running ? [
                RatingSummaryRow(assignmentId: UUID(uuidString: "7E57E57E-0000-4000-8000-00000000D003")!, ratingCount: 1, averageScore: nil, notes: nil),
                RatingSummaryRow(assignmentId: UUID(uuidString: "7E57E57E-0000-4000-8000-00000000D004")!, ratingCount: 2, averageScore: 4.5, notes: ["Looks brand new"]),
                RatingSummaryRow(assignmentId: UUID(uuidString: "7E57E57E-0000-4000-8000-00000000D005")!, ratingCount: 2, averageScore: 2, notes: []),
                RatingSummaryRow(assignmentId: UUID(uuidString: "7E57E57E-0000-4000-8000-00000000D006")!, ratingCount: 1, averageScore: nil, notes: nil)
            ] : [],
            myRatings: []
        )
    }
}

final class PreviewRemoteStore: RemoteStore, @unchecked Sendable {
    let snapshot: GroupSnapshot
    init(snapshot: GroupSnapshot) { self.snapshot = snapshot }

    func fetchSnapshot(groupID: UUID) async throws -> GroupSnapshot { snapshot }
    func saveChore(_ row: ChoreRow) async throws {}
    func saveAssignment(_ row: AssignmentRow) async throws {}
    func castValueVote(choreID: UUID, difficulty: Int, labor: Int, minutes: Int) async throws {}
    func rateAssignment(id: UUID, score: Int, note: String) async throws {}
    func updateMember(groupID: UUID, userID: UUID, shareWeight: Double, carryOverPoints: Double) async throws {}
    func updateGroup(_ update: GroupUpdate) async throws {}
    func settleDueAssignments(groupID: UUID) async throws {}
    func claimMaintenance(groupID: UUID) async throws -> Bool { false }
    func uploadProofVideo(fileURL: URL, path: String) async throws {}
    func deleteProofVideo(path: String) async throws {}
    func playableVideoURL(path: String) async throws -> URL { throw URLError(.notConnectedToInternet) }
    func changes(groupID: UUID) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

struct SharedPreviewRoot: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState

    @State private var auth = AuthStore(client: SharedPreview.offlineClient)
    @State private var groups = GroupStore(client: SharedPreview.offlineClient)
    @State private var engine: SyncEngine?
    @State private var showingInvite = false
    @State private var showingMenu = false

    @Query(filter: #Predicate<Household> { $0.isShared }) private var households: [Household]

    var body: some View {
        Group {
            if SharedPreview.has("--signed-out") {
                WelcomeView()
            } else if SharedPreview.has("--profile") {
                ProfileSetupView(suggestedName: "Alex Kerr")
            } else if SharedPreview.has("--groups") {
                GroupsView()
            } else if let engine, let household = households.first(where: { $0.id == SharedPreview.groupID }) {
                Group {
                    if household.setupStage == .running {
                        HomeView(household: household)
                    } else {
                        GroupSetupView(household: household)
                    }
                }
                .environment(engine)
                .sheet(isPresented: $showingInvite) {
                    InviteFriendsView(household: household).environment(engine).environment(groups)
                }
                .sheet(isPresented: $showingMenu) {
                    GroupSheet(household: household).environment(engine).environment(groups).environment(auth)
                }
            } else {
                SplashView()
            }
        }
        .environment(auth)
        .environment(groups)
        .task {
            groups.seedForPreview([
                .init(id: SharedPreview.groupID, name: "Flat 3B", inviteCode: "K7P4QX9A", memberCount: 3, isOwner: true, isRunning: true),
                .init(id: UUID(), name: "Beach house", inviteCode: "M2RT8WQZ", memberCount: 5, isOwner: false, isRunning: false)
            ])
            let snapshot = SharedPreview.snapshot(running: !SharedPreview.has("--setup"))
            let engine = SyncEngine(groupID: SharedPreview.groupID, currentUserID: SharedPreview.me,
                                    remote: PreviewRemoteStore(snapshot: snapshot), context: context)
            appState.activeRoommateID = SharedPreview.me
            await engine.pull()
            self.engine = engine
            try? await Task.sleep(for: .milliseconds(600))
            showingInvite = SharedPreview.has("--invite")
            showingMenu = SharedPreview.has("--group-menu")
        }
    }
}
#endif
