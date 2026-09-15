import Testing
import Foundation
import SwiftData
@testable import ChoreSplit

/// A server that lives in memory: records what it's sent, and serves whatever snapshot the
/// test sets up.
final class FakeRemoteStore: RemoteStore, @unchecked Sendable {
    enum Call: Equatable {
        case saveChore(UUID)
        case saveAssignment(UUID, videoPath: String?)
        case vote(UUID)
        case rate(UUID, Int)
        case updateMember(UUID)
        case updateGroup(String)
        case settleDue
        case claim
        case upload(String)
        case deleteVideo(String)
    }

    var calls: [Call] = []
    var snapshot: GroupSnapshot?
    var failNextWith: Error?
    var claimGranted = true

    private func record(_ call: Call) throws {
        if let error = failNextWith {
            failNextWith = nil
            throw error
        }
        calls.append(call)
    }

    func fetchSnapshot(groupID: UUID) async throws -> GroupSnapshot {
        guard let snapshot else { throw RemoteStoreError.groupUnavailable }
        return snapshot
    }
    func saveChore(_ row: ChoreRow) async throws { try record(.saveChore(row.id)) }
    func saveAssignment(_ row: AssignmentRow) async throws { try record(.saveAssignment(row.id, videoPath: row.proofVideoPath)) }
    func castValueVote(choreID: UUID, difficulty: Int, labor: Int, minutes: Int) async throws { try record(.vote(choreID)) }
    func rateAssignment(id: UUID, score: Int, note: String) async throws { try record(.rate(id, score)) }
    func updateMember(groupID: UUID, userID: UUID, shareWeight: Double, carryOverPoints: Double) async throws { try record(.updateMember(userID)) }
    func updateGroup(_ update: GroupUpdate) async throws { try record(.updateGroup(update.setupStage)) }
    func settleDueAssignments(groupID: UUID) async throws { try record(.settleDue) }
    func claimMaintenance(groupID: UUID) async throws -> Bool { try record(.claim); return claimGranted }
    func uploadProofVideo(fileURL: URL, path: String) async throws { try record(.upload(path)) }
    func deleteProofVideo(path: String) async throws { try record(.deleteVideo(path)) }
    func playableVideoURL(path: String) async throws -> URL { URL(string: "https://example.com/\(path)")! }
    func changes(groupID: UUID) -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private struct FakeRefusal: Error, RefusalCoded { var refusalCode: String? { "42501" } }

@MainActor
private struct SharedGroup {
    let container: ModelContainer
    let context: ModelContext
    let remote = FakeRemoteStore()
    let engine: SyncEngine

    let groupID = UUID()
    let me = UUID()
    let friend = UUID()
    let choreID = UUID()
    let taskID = UUID()

    init() throws {
        let schema = Schema([Household.self, Roommate.self, Chore.self, ChoreValueVote.self,
                             Assignment.self, QualityRating.self, PendingOperation.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        context = ModelContext(container)
        engine = SyncEngine(groupID: groupID, currentUserID: me, remote: remote, context: context)
    }

    func snapshot(
        taskStatus: String = "open",
        assignee: UUID? = nil,
        ratingCount: Int = 0,
        average: Double? = nil,
        notes: [String]? = nil,
        myRating: Int? = nil,
        videoPath: String? = nil,
        includeFriend: Bool = true
    ) -> GroupSnapshot {
        let now = Date()
        var members = [MemberRow(groupId: groupID, userId: me, role: "owner", shareWeight: 1, carryOverPoints: 0, paletteIndex: 0, joinedAt: now)]
        var profiles = [ProfileRow(id: me, displayName: "Alex Kerr", emoji: "🦊")]
        if includeFriend {
            members.append(MemberRow(groupId: groupID, userId: friend, role: "member", shareWeight: 1, carryOverPoints: 2, paletteIndex: 1, joinedAt: now))
            profiles.append(ProfileRow(id: friend, displayName: "Priya Shah", emoji: "🌻"))
        }
        return GroupSnapshot(
            group: GroupRow(id: groupID, name: "Flat 3B", cycleLengthDays: 7, cycleStartDate: now, setupStage: "running",
                            fairnessTolerance: 0.1, minimumRatingsToReveal: 2, ratingWindowHours: 48,
                            autoAssignEnabled: true, inviteCode: "K7P4QX9A", createdBy: me),
            members: members,
            profiles: profiles,
            chores: [ChoreRow(id: choreID, groupId: groupID, title: "Scrub the toilet", notes: "", category: "bathroom",
                              recurrence: "weekly", isActive: true, proposerId: friend, proposedDifficulty: 2,
                              proposedLabor: 2, proposedMinutes: 15, createdAt: now)],
            valueSummaries: [ValueSummaryRow(choreId: choreID, voteCount: 2, avgDifficulty: 5, avgLabor: 4, avgMinutes: 30)],
            myVotes: [MyVoteRow(choreId: choreID, difficulty: 5, labor: 4, minutes: 30)],
            assignments: [AssignmentRow(id: taskID, groupId: groupID, choreId: choreID, assigneeId: assignee ?? friend,
                                        assignedAt: now, dueDate: now.addingTimeInterval(3600), status: taskStatus, pointsQuoted: 3,
                                        awardedPoints: taskStatus == "settled" ? 2 : nil,
                                        completedAt: taskStatus == "open" ? nil : now, wasAutoAssigned: false,
                                        assignmentReason: "", proofVideoPath: videoPath, proofVideoDuration: videoPath == nil ? nil : 12)],
            ratingSummaries: taskStatus == "open" ? [] : [RatingSummaryRow(assignmentId: taskID, ratingCount: ratingCount, averageScore: average, notes: notes)],
            myRatings: myRating.map { [MyRatingRow(assignmentId: taskID, score: $0, note: "")] } ?? []
        )
    }

    func apply(_ snapshot: GroupSnapshot, protected: Set<UUID> = []) throws -> SnapshotApplier.Outcome {
        try SnapshotApplier.apply(snapshot, currentUserID: me, protectedIDs: protected, context: context)
    }

    var household: Household? { engine.household }
    func task() throws -> Assignment? {
        let id = taskID
        return try context.fetch(FetchDescriptor<Assignment>(predicate: #Predicate { $0.id == id })).first
    }
    func pending() throws -> [PendingOperation] { try context.fetch(FetchDescriptor<PendingOperation>()) }
}

@Suite("Applying the server's copy", .serialized)
@MainActor
struct SnapshotApplierTests {

    @Test("A group arrives with its members, chores and tasks")
    func buildsTheGroup() throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot())

        let household = try #require(group.household)
        #expect(household.isShared)
        #expect(household.name == "Flat 3B")
        #expect(household.inviteCode == "K7P4QX9A")
        #expect(household.setupStage == .running)
        #expect(household.sortedMembers.map(\.name).sorted() == ["Alex Kerr", "Priya Shah"])
        #expect(household.sortedMembers.first { $0.id == group.me }?.isOwner == true)

        let task = try #require(try group.task())
        #expect(task.assignee?.id == group.friend)
        #expect(task.chore?.title == "Scrub the toilet")
        #expect(task.pointsQuoted == 3)
    }

    @Test("Everyone else's votes arrive only as totals, and still price the chore")
    func choreWorthFromTotals() throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot())
        let chore = try #require(group.household?.activeChores.first)

        // Proposer said 2/2/15; two anonymous voters averaged 5/4/30.
        #expect(chore.voteCount == 2)
        #expect(abs(chore.agreedValues.difficulty - 4) < 0.001)
        #expect(abs(chore.agreedValues.labor - (10.0 / 3)) < 0.001)
        #expect(chore.points > chore.proposedPoints)
        // Only my own vote is on the phone, and it's recognised as mine.
        #expect(chore.votes.count == 1)
        let me = try #require(group.household?.sortedMembers.first { $0.id == group.me })
        #expect(chore.hasVoted(me))
    }

    @Test("A rating's score and notes stay hidden until the server reveals them")
    func ratingsRevealOnlyFromServer() throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot(taskStatus: "awaitingReview", ratingCount: 1, myRating: 4))
        let household = try #require(group.household)
        let task = try #require(try group.task())

        #expect(task.ratingCount == 1)
        #expect(task.revealedAverage(in: household) == nil)
        #expect(task.revealedNotes(in: household).isEmpty)
        let me = try #require(household.sortedMembers.first { $0.id == group.me })
        #expect(task.hasRated(me))
        #expect(Scores.awaitingRating(from: me, in: household).isEmpty)

        try group.apply(group.snapshot(taskStatus: "settled", ratingCount: 2, average: 3.5, notes: ["Spotless", "Good"], myRating: 4))
        #expect(task.revealedAverage(in: household) == 3.5)
        #expect(task.revealedNotes(in: household) == ["Good", "Spotless"])
        #expect(task.effectivePoints == 2)
    }

    @Test("A refresh updates things in place, keeping what only lives on this phone")
    func updatesInPlace() throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot(assignee: group.me))
        let task = try #require(try group.task())
        let reminder = Date().addingTimeInterval(1800)
        task.reminderDate = reminder
        let salt = task.anonymitySalt

        var next = group.snapshot(assignee: group.me)
        next.assignments[0].dueDate = Date().addingTimeInterval(7200)
        try group.apply(next)

        let same = try #require(try group.task())
        #expect(same === task)
        #expect(same.reminderDate == reminder)
        #expect(same.anonymitySalt == salt)
        #expect(abs(same.dueDate.timeIntervalSince(next.assignments[0].dueDate)) < 1)
    }

    @Test("Things removed on the server go; things with unsent changes stay")
    func deletionsRespectPendingChanges() throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot())

        var emptied = group.snapshot()
        emptied.assignments = []
        emptied.chores = []
        try group.apply(emptied, protected: [group.taskID])
        #expect(try group.task() != nil)
        #expect(group.household?.chores?.isEmpty == true)

        try group.apply(emptied)
        #expect(try group.task() == nil)
    }

    @Test("Someone who leaves drops off the member list, but their finished work stays")
    func departedMembers() throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot(taskStatus: "settled", ratingCount: 1))
        try group.apply(group.snapshot(taskStatus: "settled", ratingCount: 1, includeFriend: false))

        #expect(group.household?.sortedMembers.map(\.id) == [group.me])
        let task = try #require(try group.task())
        #expect(task.assignee == nil)
        #expect(task.status == .settled)
    }

    @Test("A task given to me on another phone is flagged for a reminder")
    func newTasksForMe() throws {
        let group = try SharedGroup()
        let outcome = try group.apply(group.snapshot(assignee: group.me))
        #expect(outcome.newTasksForMe == [group.taskID])
        let again = try group.apply(group.snapshot(assignee: group.me))
        #expect(again.newTasksForMe.isEmpty)
    }

    @Test("My settled task's uploaded video is flagged for deletion")
    func expiredVideos() throws {
        let group = try SharedGroup()
        let path = "\(group.groupID.uuidString.lowercased())/\(group.taskID.uuidString.lowercased()).mp4"
        let outcome = try group.apply(group.snapshot(taskStatus: "settled", assignee: group.me, ratingCount: 1, videoPath: path))
        #expect(outcome.expiredVideoPaths.map(\.path) == [path])

        let theirs = try SharedGroup()
        let none = try theirs.apply(theirs.snapshot(taskStatus: "settled", ratingCount: 1, videoPath: path))
        #expect(none.expiredVideoPaths.isEmpty)
    }
}

@Suite("Sending changes", .serialized)
@MainActor
struct SyncEngineTests {

    @Test("Changes made on the phone are queued, then sent in order")
    func queuesAndSendsInOrder() async throws {
        let group = try SharedGroup()
        var fresh = group.snapshot(taskStatus: "awaitingReview", ratingCount: 0)
        fresh.myVotes = []   // I haven't priced this chore yet
        try group.apply(fresh)
        HouseholdActions.sync = group.engine
        defer { HouseholdActions.sync = nil }

        let household = try #require(group.household)
        let me = try #require(household.sortedMembers.first { $0.id == group.me })
        let chore = try #require(household.activeChores.first)
        let task = try #require(try group.task())

        HouseholdActions.submitValueVote(for: chore, by: me, difficulty: 3, labor: 3, minutes: 20, context: group.context)
        HouseholdActions.submitQualityRating(for: task, by: me, score: 4, in: household, context: group.context)
        #expect(try group.pending().count >= 2)

        await group.engine.flush()

        #expect(try group.pending().isEmpty)
        #expect(group.remote.calls.prefix(2) == [.vote(group.choreID), .rate(group.taskID, 4)])
        // Each change goes to the server exactly once.
        #expect(group.remote.calls.filter { $0 == .rate(group.taskID, 4) }.count == 1)
    }

    @Test("A refresh while changes are already sending doesn't send them twice")
    func overlappingFlushes() async throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot())
        HouseholdActions.sync = group.engine
        defer { HouseholdActions.sync = nil }
        let chore = try #require(group.household?.activeChores.first)

        HouseholdActions.choreSaved(chore)          // starts a background flush
        async let first: Void = group.engine.flush()
        async let second: Void = group.engine.refresh()
        _ = await (first, second)

        #expect(group.remote.calls.filter { $0 == .saveChore(group.choreID) }.count == 1)
    }

    @Test("In a shared group, only the person doing a task is reminded on their own phone")
    func remindersStayWithTheAssignee() throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot())
        HouseholdActions.sync = group.engine
        defer { HouseholdActions.sync = nil }
        let household = try #require(group.household)
        let me = try #require(household.sortedMembers.first { $0.id == group.me })
        let friend = try #require(household.sortedMembers.first { $0.id == group.friend })

        #expect(HouseholdActions.remindsOnThisPhone(for: me, in: household))
        #expect(!HouseholdActions.remindsOnThisPhone(for: friend, in: household))

        // On the demo's shared phone, everyone is reminded here.
        let demo = try TestHousehold(choreSpecs: [])
        #expect(HouseholdActions.remindsOnThisPhone(for: demo.members[1], in: demo.household))
    }

    @Test("Nothing is recorded for the on-device demo household")
    func demoHouseholdStaysLocal() throws {
        let group = try SharedGroup()
        HouseholdActions.sync = group.engine
        defer { HouseholdActions.sync = nil }

        let local = try TestHousehold(choreSpecs: [("Wash up", 2, 2, 20)])
        local.assign(local.chores[0], to: local.members[0])
        #expect(try group.pending().isEmpty)
    }

    @Test("Going offline keeps the queue intact and in order")
    func offlineKeepsQueue() async throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot())
        HouseholdActions.sync = group.engine
        defer { HouseholdActions.sync = nil }
        let chore = try #require(group.household?.activeChores.first)

        HouseholdActions.choreSaved(chore)
        HouseholdActions.householdSaved(try #require(group.household))
        group.remote.failNextWith = URLError(.notConnectedToInternet)

        await group.engine.flush()
        #expect(try group.pending().count == 2)
        #expect(group.remote.calls.isEmpty)
        #expect(group.engine.lastError?.contains("Offline") == true)

        await group.engine.flush()
        #expect(try group.pending().isEmpty)
        #expect(group.remote.calls == [.saveChore(group.choreID), .updateGroup("running")])
    }

    @Test("A change the server refuses is dropped, so it can't block the rest")
    func refusalIsDropped() async throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot())
        HouseholdActions.sync = group.engine
        defer { HouseholdActions.sync = nil }
        let chore = try #require(group.household?.activeChores.first)

        HouseholdActions.choreSaved(chore)
        HouseholdActions.householdSaved(try #require(group.household))
        group.remote.failNextWith = FakeRefusal()

        await group.engine.flush()
        #expect(try group.pending().isEmpty)
        #expect(group.remote.calls == [.updateGroup("running")])
        #expect(group.engine.lastError != nil)
    }

    @Test("Finishing with a video uploads the video before saving the task")
    func videoUploadsFirst() async throws {
        let group = try SharedGroup()
        try group.apply(group.snapshot(assignee: group.me))
        HouseholdActions.sync = group.engine
        defer { HouseholdActions.sync = nil }
        let household = try #require(group.household)
        let task = try #require(try group.task())

        let clip = try await DemoVideo.make(seconds: 1, size: CGSize(width: 64, height: 64), color: .systemTeal)
        let prepared = try await ProofVideoStore.prepare(from: clip)
        try? FileManager.default.removeItem(at: clip)
        task.proofVideoFilename = try ProofVideoStore.commit(prepared, for: task.id)
        defer { task.proofVideoFilename.map(ProofVideoStore.delete(filename:)) }

        HouseholdActions.markComplete(task, in: household, context: group.context)
        await group.engine.flush()

        let path = Backend.proofVideoPath(groupID: group.groupID, assignmentID: group.taskID)
        let firstSave = group.remote.calls.firstIndex(of: .saveAssignment(group.taskID, videoPath: path))
        let upload = group.remote.calls.firstIndex(of: .upload(path))
        #expect(upload != nil)
        #expect(firstSave != nil)
        #expect((upload ?? .max) < (firstSave ?? .min))
        #expect(task.proofVideoRemotePath == path)
    }

    @Test("A refresh doesn't undo a change that hasn't been sent yet")
    func pullProtectsUnsentChanges() async throws {
        let group = try SharedGroup()
        group.remote.snapshot = group.snapshot(assignee: group.me)
        await group.engine.pull()
        HouseholdActions.sync = group.engine
        defer { HouseholdActions.sync = nil }

        let task = try #require(try group.task())
        let household = try #require(group.household)
        group.remote.failNextWith = URLError(.notConnectedToInternet)
        HouseholdActions.markSkipped(task, context: group.context)
        try? await Task.sleep(for: .milliseconds(50))   // let the scheduled flush hit the outage

        await group.engine.pull()   // server still says "open"
        #expect(task.status == .skipped)

        await group.engine.refresh()
        #expect(group.remote.calls.contains(.saveAssignment(group.taskID, videoPath: nil)))
        _ = household
    }

    @Test("Maintenance settles first, and only hands out chores when this phone has the claim")
    func maintenanceNeedsTheClaim() async throws {
        let group = try SharedGroup()
        group.remote.snapshot = group.snapshot()
        group.remote.claimGranted = false

        await group.engine.maintain()
        #expect(group.remote.calls.first == .settleDue)
        #expect(group.remote.calls.contains(.claim))
        #expect(!group.remote.calls.contains { if case .saveAssignment = $0 { return true } else { return false } })
    }

    @Test("Leaving a group shows up as the group becoming unavailable")
    func groupUnavailable() async throws {
        let group = try SharedGroup()
        group.remote.snapshot = nil
        await group.engine.pull()
        #expect(group.engine.groupUnavailable)
    }
}

@Suite("Server rows")
struct RemoteRowCodingTests {

    @Test("Rows are written with the server's column names")
    func snakeCaseKeys() throws {
        let row = AssignmentRow(id: UUID(), groupId: UUID(), choreId: nil, assigneeId: UUID(), assignedAt: Date(), dueDate: Date(),
                                status: "open", pointsQuoted: 3, awardedPoints: nil, completedAt: nil, wasAutoAssigned: true,
                                assignmentReason: "", proofVideoPath: nil, proofVideoDuration: nil)
        let json = try #require(String(data: try JSONEncoder().encode(row), encoding: .utf8))
        for key in ["\"group_id\"", "\"points_quoted\"", "\"due_date\"", "\"was_auto_assigned\"", "\"proof_video_path\":null"] {
            #expect(json.contains(key), "missing \(key)")
        }
    }

    @Test("A summary with hidden scores decodes as nil, not zero")
    func hiddenScoresDecodeAsNil() throws {
        let json = #"[{"assignment_id":"A0000000-0000-4000-8000-000000000001","rating_count":1,"average_score":null,"notes":null}]"#
        let rows = try JSONDecoder().decode([RatingSummaryRow].self, from: Data(json.utf8))
        #expect(rows.first?.ratingCount == 1)
        #expect(rows.first?.averageScore == nil)
        #expect(rows.first?.notes == nil)
    }

    @Test("Queued operations survive being saved and read back")
    func operationsRoundTrip() throws {
        let op = SyncOperation.saveAssignment(
            AssignmentRow(id: UUID(), groupId: UUID(), choreId: UUID(), assigneeId: UUID(), assignedAt: Date(timeIntervalSince1970: 1_000),
                          dueDate: Date(timeIntervalSince1970: 2_000), status: "awaitingReview", pointsQuoted: 2, awardedPoints: nil,
                          completedAt: Date(timeIntervalSince1970: 1_500), wasAutoAssigned: false, assignmentReason: "Added by Alex",
                          proofVideoPath: nil, proofVideoDuration: 12),
            localVideoFilename: "clip.mp4"
        )
        let decoded = try JSONDecoder().decode(SyncOperation.self, from: JSONEncoder().encode(op))
        #expect(decoded == op)
    }
}
