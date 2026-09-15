import Testing
import Foundation
import SwiftData
@testable import ChoreSplit

@Suite("Scoreboard")
@MainActor
struct ScoresTests {

    private func makeFlat() throws -> TestHousehold {
        try TestHousehold(choreSpecs: [
            ("Clean the oven", 5, 4, 60),        // 4 pts
            ("Scrub the toilet", 4, 3, 15),      // 3 pts
            ("Wash up", 2, 2, 20),               // 2 pts
            ("Water the plants", 1, 1, 10)       // 1 pt
        ])
    }

    @Test("Only finished tasks earn points — open and skipped ones don't")
    func onlyFinishedTasksCount() throws {
        let flat = try makeFlat()
        let person = flat.members[0]

        flat.assign(flat.chores[0], to: person)                                   // still open
        HouseholdActions.markSkipped(flat.assign(flat.chores[1], to: person), context: flat.context)
        HouseholdActions.markComplete(flat.assign(flat.chores[2], to: person), in: flat.household, context: flat.context)

        let entry = try #require(Scores.board(for: flat.household).first { $0.roommate.id == person.id })
        #expect(entry.thisCycle == 2)
        #expect(entry.tasksThisCycle == 1)
        #expect(Scores.completedTasks(by: person, in: flat.household).count == 1)
    }

    @Test("A rated task counts at what it actually paid")
    func settledTasksCountAtTheirPayout() throws {
        let flat = try makeFlat()
        let task = flat.assign(flat.chores[0], to: flat.members[0])          // 4 pts
        HouseholdActions.markComplete(task, in: flat.household, context: flat.context)
        for rater in [flat.members[1], flat.members[2]] {
            HouseholdActions.submitQualityRating(for: task, by: rater, score: 1, in: flat.household, context: flat.context)
        }

        let entry = try #require(Scores.board(for: flat.household).first { $0.roommate.id == flat.members[0].id })
        #expect(entry.thisCycle == 2)   // one star pays half
    }

    @Test("The board is ordered highest score first")
    func ordering() throws {
        let flat = try makeFlat()
        HouseholdActions.markComplete(flat.assign(flat.chores[3], to: flat.members[0]), in: flat.household, context: flat.context)
        HouseholdActions.markComplete(flat.assign(flat.chores[0], to: flat.members[1]), in: flat.household, context: flat.context)
        HouseholdActions.markComplete(flat.assign(flat.chores[2], to: flat.members[2]), in: flat.household, context: flat.context)

        let order = Scores.board(for: flat.household).map(\.roommate.id)
        #expect(order == [flat.members[1].id, flat.members[2].id, flat.members[0].id])
    }

    @Test("Tasks finished before this cycle count all-time, not this week")
    func earlierTasks() throws {
        let flat = try makeFlat()
        let task = flat.assign(flat.chores[1], to: flat.members[0])
        HouseholdActions.markComplete(task, in: flat.household, context: flat.context)
        task.completedAt = Calendar.current.date(byAdding: .day, value: -10, to: flat.household.currentCycleStart)

        let entry = try #require(Scores.board(for: flat.household).first { $0.roommate.id == flat.members[0].id })
        #expect(entry.thisCycle == 0)
        #expect(entry.allTime == 3)
    }

    @Test("You're asked to rate other people's finished tasks — not your own, and not twice")
    func ratingQueue() throws {
        let flat = try makeFlat()
        let mine = flat.assign(flat.chores[0], to: flat.members[0])
        let theirs = flat.assign(flat.chores[1], to: flat.members[1])
        let unfinished = flat.assign(flat.chores[2], to: flat.members[2])
        HouseholdActions.markComplete(mine, in: flat.household, context: flat.context)
        HouseholdActions.markComplete(theirs, in: flat.household, context: flat.context)

        let queue = Scores.awaitingRating(from: flat.members[0], in: flat.household)
        #expect(queue.map(\.id) == [theirs.id])
        #expect(!queue.contains { $0.id == unfinished.id })

        HouseholdActions.submitQualityRating(for: theirs, by: flat.members[0], score: 4, in: flat.household, context: flat.context)
        #expect(Scores.awaitingRating(from: flat.members[0], in: flat.household).isEmpty)
    }
}
