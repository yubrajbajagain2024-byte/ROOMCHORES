import Foundation
import SwiftData
import Observation

/// Keeps one shared group in step between this phone and the server.
///
/// Changes are made locally first and queued, so the app never waits on the network to tick
/// something off. The queue is sent oldest-first; the group is then re-fetched and applied.
/// While the group is open, changes from other phones arrive over Supabase Realtime and trigger
/// a refresh.
@Observable
final class SyncEngine: HouseholdSyncing {

    let groupID: UUID
    let currentUserID: UUID

    private(set) var isSyncing = false
    private(set) var lastError: String?
    private(set) var pendingCount = 0
    /// Set when the server no longer lets this user see the group — they left, or were removed.
    private(set) var groupUnavailable = false

    @ObservationIgnored private let remote: RemoteStore
    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    /// Set when a flush is asked for while one is already running, so it goes round again
    /// instead of a second flush running alongside and sending the same change twice.
    @ObservationIgnored private var flushRequested = false
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var pendingPull: Task<Void, Never>?
    /// Failures before an unexplained error is given up on, so one bad change can't block the queue.
    @ObservationIgnored private let maximumAttempts = 5

    init(groupID: UUID, currentUserID: UUID, remote: RemoteStore, context: ModelContext) {
        self.groupID = groupID
        self.currentUserID = currentUserID
        self.remote = remote
        self.context = context
        self.pendingCount = (try? pendingOperations().count) ?? 0
    }

    var household: Household? {
        let id = groupID
        return try? context.fetch(FetchDescriptor<Household>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: - Recording changes

    func choreChanged(_ chore: Chore) {
        guard chore.household?.id == groupID else { return }
        enqueue(.saveChore(ChoreRow(chore: chore, groupID: groupID)))
    }

    func assignmentChanged(_ assignment: Assignment) {
        guard assignment.household?.id == groupID else { return }
        let unsentVideo = assignment.proofVideoRemotePath == nil ? assignment.proofVideoFilename : nil
        enqueue(.saveAssignment(AssignmentRow(assignment: assignment, groupID: groupID), localVideoFilename: unsentVideo))
    }

    func valueVoteCast(on chore: Chore, difficulty: Int, labor: Int, minutes: Int) {
        guard chore.household?.id == groupID else { return }
        enqueue(.castValueVote(choreID: chore.id, difficulty: difficulty, labor: labor, minutes: minutes))
    }

    func qualityRated(_ assignment: Assignment, score: Int, note: String) {
        guard assignment.household?.id == groupID else { return }
        enqueue(.rateAssignment(assignmentID: assignment.id, score: score, note: note))
    }

    func memberChanged(_ roommate: Roommate) {
        guard roommate.household?.id == groupID else { return }
        enqueue(.updateMember(groupID: groupID, userID: roommate.id,
                              shareWeight: roommate.shareWeight, carryOverPoints: roommate.carryOverPoints))
    }

    func householdChanged(_ household: Household) {
        guard household.id == groupID else { return }
        enqueue(.updateGroup(GroupUpdate(household: household)))
    }

    func proofVideoExpired(path: String) {
        enqueue(.deleteProofVideo(path: path))
    }

    private func enqueue(_ operation: SyncOperation) {
        guard let pending = try? PendingOperation(groupID: groupID, operation: operation) else { return }
        context.insert(pending)
        try? context.save()
        pendingCount += 1
        scheduleFlush()
    }

    // MARK: - Sending

    func scheduleFlush() {
        flushRequested = true
        guard flushTask == nil else { return }
        flushTask = Task { @MainActor [weak self] in
            while let self, self.flushRequested {
                self.flushRequested = false
                await self.drainQueue()
            }
            self?.flushTask = nil
        }
    }

    /// Send everything queued and wait until it's done. Only one flush ever runs at a time.
    @MainActor
    func flush() async {
        scheduleFlush()
        await flushTask?.value
    }

    /// Send queued changes, oldest first. Stops at the first network failure so the order holds;
    /// a change the server refuses is dropped, and the next refresh shows the server's version.
    @MainActor
    private func drainQueue() async {
        defer { pendingCount = (try? pendingOperations().count) ?? 0 }
        var refusal: String?

        while let next = try? pendingOperations().first {
            guard let operation = next.operation else {
                context.delete(next)
                try? context.save()
                continue
            }
            do {
                try await send(operation)
                context.delete(next)
                try? context.save()
            } catch {
                let message = BackendError.message(for: error)
                next.attempts += 1
                next.lastError = message

                if BackendError.isTransient(error) {
                    // Offline: keep everything, in order, and try again later.
                    lastError = "Offline — your changes will sync when you're back online."
                    try? context.save()
                    return
                }

                if SyncEngine.isRefusal(error) || next.attempts >= maximumAttempts {
                    // Retrying won't help; drop it so the changes behind it can go through.
                    refusal = message
                    context.delete(next)
                    try? context.save()
                    continue
                }
                lastError = message
                try? context.save()
                return
            }
        }
        // Queue empty. A refused change stays reported rather than being cleared by later successes.
        lastError = refusal
    }

    @MainActor
    private func send(_ operation: SyncOperation) async throws {
        switch operation {
        case .saveChore(let row):
            try await remote.saveChore(row)

        case .saveAssignment(var row, let localVideoFilename):
            if row.proofVideoPath == nil, let filename = localVideoFilename,
               let fileURL = ProofVideoStore.existingURL(for: filename) {
                let path = Backend.proofVideoPath(groupID: groupID, assignmentID: row.id)
                try await remote.uploadProofVideo(fileURL: fileURL, path: path)
                row.proofVideoPath = path
                assignment(id: row.id)?.proofVideoRemotePath = path
            }
            try await remote.saveAssignment(row)

        case .castValueVote(let choreID, let difficulty, let labor, let minutes):
            try await remote.castValueVote(choreID: choreID, difficulty: difficulty, labor: labor, minutes: minutes)

        case .rateAssignment(let assignmentID, let score, let note):
            try await remote.rateAssignment(id: assignmentID, score: score, note: note)

        case .updateMember(let groupID, let userID, let shareWeight, let carryOverPoints):
            try await remote.updateMember(groupID: groupID, userID: userID, shareWeight: shareWeight, carryOverPoints: carryOverPoints)

        case .updateGroup(let update):
            try await remote.updateGroup(update)

        case .deleteProofVideo(let path):
            try await remote.deleteProofVideo(path: path)
        }
    }

    // MARK: - Receiving

    /// Fetch the group and apply it.
    @MainActor
    func pull() async {
        isSyncing = true
        defer { isSyncing = false }
        do {
            let snapshot = try await remote.fetchSnapshot(groupID: groupID)
            let protected = Set((try pendingOperations()).compactMap { $0.operation?.protectedEntityID })
            let outcome = try SnapshotApplier.apply(snapshot, currentUserID: currentUserID, protectedIDs: protected, context: context)
            groupUnavailable = false
            if pendingCount == 0 { lastError = nil }
            handle(outcome)
        } catch RemoteStoreError.groupUnavailable {
            groupUnavailable = true
        } catch {
            lastError = BackendError.isTransient(error)
                ? "Offline — showing what was last synced."
                : BackendError.message(for: error)
        }
    }

    /// Send what's queued, then fetch.
    @MainActor
    func refresh() async {
        await flush()
        await pull()
    }

    /// The periodic job: settle tasks whose ratings are done, then — if no other phone is
    /// already doing it — roll the cycle and hand out catch-up chores.
    @MainActor
    func maintain() async {
        await flush()
        try? await remote.settleDueAssignments(groupID: groupID)
        await pull()

        guard let household, household.setupStage == .running,
              (try? await remote.claimMaintenance(groupID: groupID)) == true
        else { return }

        HouseholdActions.runMaintenance(for: household, context: context, settlesLocally: false)
        await flush()
    }

    @MainActor
    private func handle(_ outcome: SnapshotApplier.Outcome) {
        for expired in outcome.expiredVideoPaths {
            guard let assignment = assignment(id: expired.assignmentID) else { continue }
            enqueue(.deleteProofVideo(path: expired.path))
            assignment.proofVideoRemotePath = nil
            assignmentChanged(assignment)
        }

        for id in outcome.newTasksForMe {
            guard let assignment = assignment(id: id), let me = assignment.assignee else { continue }
            assignment.reminderDate = HouseholdActions.defaultReminderDate(for: assignment.dueDate)
            assignment.reminderSpokenText = ReminderPhrase.sentence(for: assignment, assigneeName: me.name)
            let reminder = NotificationService.ReminderRequest(assignment: assignment, assigneeName: me.name)
            Task { await NotificationService.shared.scheduleReminder(reminder) }
        }
        try? context.save()
    }

    // MARK: - Live updates

    /// Listen for other phones' changes, refreshing shortly after each burst.
    @MainActor
    func startLive() {
        guard liveTask == nil else { return }
        let stream = remote.changes(groupID: groupID)
        liveTask = Task { @MainActor [weak self] in
            for await _ in stream {
                self?.schedulePull()
            }
        }
    }

    @MainActor
    func stop() {
        liveTask?.cancel()
        liveTask = nil
        pendingPull?.cancel()
        if HouseholdActions.sync === self {
            HouseholdActions.sync = nil
        }
    }

    @MainActor
    private func schedulePull() {
        pendingPull?.cancel()
        pendingPull = Task { @MainActor [weak self] in
            // One refresh for a burst of changes, not one per row.
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await self?.pull()
        }
    }

    /// Playable URL for a video that's only on the server.
    func playableVideoURL(path: String) async -> URL? {
        try? await remote.playableVideoURL(path: path)
    }

    // MARK: - Helpers

    private func pendingOperations() throws -> [PendingOperation] {
        let id = groupID
        var descriptor = FetchDescriptor<PendingOperation>(predicate: #Predicate { $0.groupID == id })
        descriptor.sortBy = [SortDescriptor(\.createdAt)]
        return try context.fetch(descriptor)
    }

    private func assignment(id: UUID) -> Assignment? {
        try? context.fetch(FetchDescriptor<Assignment>(predicate: #Predicate { $0.id == id })).first
    }

    /// The server said no — a rule, a constraint, or a message from a database function.
    /// Retrying the same change won't help.
    static func isRefusal(_ error: Error) -> Bool {
        guard let code = (error as? RefusalCoded)?.refusalCode else { return false }
        return ["42", "23", "22", "P0", "PG"].contains { code.hasPrefix($0) }
    }
}

/// Errors that carry a Postgres error code.
protocol RefusalCoded {
    var refusalCode: String? { get }
}
