import Testing
import Foundation
@testable import ChoreSplit

@Suite("Anonymity")
struct AnonymityTests {

    @Test("The same roommate always produces the same token for one chore")
    func stableWithinASalt() {
        let salt = AnonymityService.newSalt()
        let id = UUID()
        #expect(AnonymityService.token(for: id, salt: salt) == AnonymityService.token(for: id, salt: salt))
    }

    @Test("Two roommates never collide")
    func distinctPerPerson() {
        let salt = AnonymityService.newSalt()
        #expect(AnonymityService.token(for: UUID(), salt: salt) != AnonymityService.token(for: UUID(), salt: salt))
    }

    @Test("The same person looks different on different chores")
    func unlinkableAcrossChores() {
        // Without a per-chore salt you could line up two rating tables and see that the
        // same token appears in both, which is most of the way to identifying someone.
        let id = UUID()
        let first = AnonymityService.token(for: id, salt: AnonymityService.newSalt())
        let second = AnonymityService.token(for: id, salt: AnonymityService.newSalt())
        #expect(first != second)
    }

    @Test("Tokens don't contain the raw identifier")
    func doesNotLeakID() {
        let id = UUID()
        let token = AnonymityService.token(for: id, salt: AnonymityService.newSalt())
        #expect(!token.lowercased().contains(id.uuidString.lowercased()))
        #expect(token.count == 64)
    }
}
