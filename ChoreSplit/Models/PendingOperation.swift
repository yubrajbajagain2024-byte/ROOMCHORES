import Foundation
import SwiftData

/// A change made on this phone that hasn't reached the server yet.
///
/// Every edit is saved locally first, so the app works on the train, and queued here in order.
/// The sync engine sends them one at a time, oldest first, and removes each once the server
/// has it.
@Model
final class PendingOperation {
    var id: UUID = UUID()
    var groupID: UUID = UUID()
    var createdAt: Date = Date()
    var payload: Data = Data()
    var attempts: Int = 0
    var lastError: String?

    init(groupID: UUID, operation: SyncOperation) throws {
        self.id = UUID()
        self.groupID = groupID
        self.createdAt = Date()
        self.payload = try JSONEncoder().encode(operation)
    }

    var operation: SyncOperation? {
        try? JSONDecoder().decode(SyncOperation.self, from: payload)
    }
}

/// The kinds of change a phone can send.
enum SyncOperation: Codable, Equatable {
    case saveChore(ChoreRow)
    /// `localVideoFilename` is the proof video still on this phone, uploaded before the row is saved.
    case saveAssignment(AssignmentRow, localVideoFilename: String?)
    case castValueVote(choreID: UUID, difficulty: Int, labor: Int, minutes: Int)
    case rateAssignment(assignmentID: UUID, score: Int, note: String)
    case updateMember(groupID: UUID, userID: UUID, shareWeight: Double, carryOverPoints: Double)
    case updateGroup(GroupUpdate)
    case deleteProofVideo(path: String)

    /// The chore or assignment this change touches, so a refresh from the server doesn't
    /// overwrite it before it has been sent.
    var protectedEntityID: UUID? {
        switch self {
        case .saveChore(let row):             return row.id
        case .saveAssignment(let row, _):     return row.id
        case .castValueVote(let id, _, _, _): return id
        case .rateAssignment(let id, _, _):   return id
        default:                              return nil
        }
    }
}
