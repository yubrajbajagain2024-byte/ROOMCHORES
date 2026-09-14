import Testing
import Foundation
import SwiftData
@testable import ChoreSplit

/// Builds a throwaway in-memory household so the engine can be exercised against real
/// SwiftData objects rather than stand-ins.
@MainActor
struct TestHousehold {
    let container: ModelContainer
    let context: ModelContext
    let household: Household
    var members: [Roommate] = []
    var chores: [Chore] = []

    init(memberCount: Int = 3, choreSpecs: [(String, Int, Int, Int)] = []) throws {
        let schema = Schema([
            Household.self, Roommate.self, Chore.self,
            ChoreValueVote.self, Assignment.self, QualityRating.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)

        household = Household(name: "Test flat", cycleLengthDays: 7)
        context.insert(household)

        for index in 0..<memberCount {
            let member = Roommate(name: "Person \(index)", paletteIndex: index)
            member.household = household
            context.insert(member)
            members.append(member)
        }

        for (title, difficulty, labor, minutes) in choreSpecs {
            let chore = Chore(
                title: title,
                recurrence: .weekly,
                difficulty: difficulty,
                labor: labor,
                minutes: minutes,
                proposerID: members.first?.id
            )
            chore.household = household
            context.insert(chore)
            chores.append(chore)
        }
        try context.save()
    }

    @discardableResult
    func assign(_ chore: Chore, to member: Roommate) -> Assignment {
        HouseholdActions.assign(
            chore: chore,
            to: member,
            due: Date().addingTimeInterval(3600),
            in: household,
            context: context,
            scheduleReminder: false
        )
    }

    func standing(for member: Roommate) -> MemberStanding? {
        FairnessEngine.standings(for: household).first { $0.roommate.id == member.id }
    }
}

private let sampleChores: [(String, Int, Int, Int)] = [
    ("Deep clean the bathroom", 4, 4, 45),
    ("Grocery run", 3, 4, 60),
    ("Vacuum", 2, 3, 25),
    ("Wash up", 2, 2, 20),
    ("Mop the floor", 2, 3, 20),
    ("Sort recycling", 2, 2, 15),
    ("Take the bins out", 1, 2, 5),
    ("Water the plants", 1, 1, 10),
    ("Wipe the counters", 1, 1, 10)
]

@Suite("Fairness")
@MainActor
struct FairnessEngineTests {

    @Test("An empty household doesn't crash or invent standings")
    func emptyHousehold() throws {
        let flat = try TestHousehold(memberCount: 0)
        #expect(FairnessEngine.standings(for: flat.household).isEmpty)
        #expect(FairnessEngine.nextInLine(for: flat.household) == nil)
        #expect(FairnessEngine.catchUpPlan(for: flat.household).isEmpty)
    }

    @Test("Targets split the work that's actually on the table")
    func targetsSplitThePool() throws {
        let flat = try TestHousehold(choreSpecs: sampleChores)
        flat.assign(flat.chores[0], to: flat.members[0])
        flat.assign(flat.chores[1], to: flat.members[0])

        let standings = FairnessEngine.standings(for: flat.household)
        let pool = flat.chores[0].points + flat.chores[1].points
        let totalTarget = standings.reduce(0) { $0 + $1.target }

        #expect(abs(totalTarget - Double(pool)) < 0.01)
        // Three equal shares of the same pool.
        for standing in standings {
            #expect(abs(standing.target - Double(pool) / 3) < 0.01)
        }
    }

    @Test("A reduced share lowers that person's target")
    func shareWeightScalesTheTarget() throws {
        let flat = try TestHousehold(choreSpecs: sampleChores)
        flat.members[2].shareWeight = 0.5
        flat.assign(flat.chores[0], to: flat.members[0])
        flat.assign(flat.chores[1], to: flat.members[1])

        let full = try #require(flat.standing(for: flat.members[0]))
        let half = try #require(flat.standing(for: flat.members[2]))
        #expect(half.target < full.target)
        #expect(abs(half.target - full.target / 2) < 0.01)
    }

    @Test("The next chore goes to whoever is carrying least")
    func nextInLineIsTheLightestLoad() throws {
        let flat = try TestHousehold(choreSpecs: sampleChores)
        flat.assign(flat.chores[0], to: flat.members[0])
        flat.assign(flat.chores[1], to: flat.members[0])
        flat.assign(flat.chores[2], to: flat.members[1])

        // Person 2 has done nothing at all.
        #expect(FairnessEngine.nextInLine(for: flat.household)?.id == flat.members[2].id)
    }

    @Test("Someone well below their share is flagged as behind")
    func behindDetection() throws {
        let flat = try TestHousehold(choreSpecs: sampleChores)
        for chore in flat.chores.prefix(4) {
            flat.assign(chore, to: flat.members[0])
        }

        let slacker = try #require(flat.standing(for: flat.members[2]))
        let worker = try #require(flat.standing(for: flat.members[0]))
        #expect(slacker.isBehind(tolerance: 0.1))
        #expect(worker.isAhead(tolerance: 0.1))
    }

    @Test("Catch-up chores go to the people who are behind")
    func catchUpTargetsTheRightPeople() throws {
        let flat = try TestHousehold(choreSpecs: sampleChores)
        flat.assign(flat.chores[0], to: flat.members[0])
        flat.assign(flat.chores[1], to: flat.members[0])

        let plan = FairnessEngine.catchUpPlan(for: flat.household)
        #expect(!plan.isEmpty)
        // Nothing should land on the person already carrying everything.
        #expect(!plan.contains { $0.roommate.id == flat.members[0].id })
    }

    @Test("Applying the plan leaves the household balanced")
    func catchUpActuallyBalances() throws {
        let flat = try TestHousehold(choreSpecs: sampleChores)
        flat.assign(flat.chores[0], to: flat.members[0])
        flat.assign(flat.chores[1], to: flat.members[0])
        flat.assign(flat.chores[2], to: flat.members[0])

        let plan = FairnessEngine.catchUpPlan(for: flat.household)
        HouseholdActions.apply(plan, in: flat.household, context: flat.context)

        // Whatever is left over must be inside tolerance, or there was simply nothing
        // left to hand out that would fit.
        let remaining = FairnessEngine.catchUpPlan(for: flat.household)
        #expect(remaining.isEmpty)
    }

    @Test("Repeated balancing settles instead of assigning forever")
    func catchUpConverges() throws {
        // Handing someone a chore raises everyone's target, so a naive planner keeps
        // finding a new person "behind" on every pass. This is the regression guard.
        let flat = try TestHousehold(choreSpecs: sampleChores)
        flat.assign(flat.chores[0], to: flat.members[0])

        var rounds = 0
        while rounds < 25 {
            let plan = FairnessEngine.catchUpPlan(for: flat.household)
            if plan.isEmpty { break }
            HouseholdActions.apply(plan, in: flat.household, context: flat.context)
            rounds += 1
        }

        #expect(rounds < 25, "catch-up assignment never settled")
        #expect(FairnessEngine.catchUpPlan(for: flat.household).isEmpty)
    }

    @Test("Nobody is handed a chore that's already on someone's list")
    func noDoubleAssignment() throws {
        let flat = try TestHousehold(choreSpecs: sampleChores)
        flat.assign(flat.chores[0], to: flat.members[0])

        let available = FairnessEngine.availableChores(in: flat.household)
        #expect(!available.contains { $0.id == flat.chores[0].id })

        let plan = FairnessEngine.catchUpPlan(for: flat.household)
        let assignedTitles = plan.map(\.chore.id)
        #expect(Set(assignedTitles).count == assignedTitles.count)
    }

    @Test("Rolling the cycle carries part of the gap forward")
    func cycleRollCarriesDebt() throws {
        let flat = try TestHousehold(choreSpecs: sampleChores)
        for chore in flat.chores.prefix(4) {
            flat.assign(chore, to: flat.members[0])
        }

        let before = try #require(flat.standing(for: flat.members[2]))
        #expect(before.deficit > 0)

        FairnessEngine.rollCycle(for: flat.household)

        // The person who did nothing starts the next cycle owing points.
        #expect(flat.members[2].carryOverPoints > 0)
        // And the one who did everything starts with credit.
        #expect(flat.members[0].carryOverPoints < 0)
        // Carry-over is capped so a bad cycle is recoverable.
        #expect(abs(flat.members[2].carryOverPoints) <= 30)
    }
}
