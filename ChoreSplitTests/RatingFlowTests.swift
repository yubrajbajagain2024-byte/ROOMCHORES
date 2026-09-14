import Testing
import Foundation
import SwiftData
@testable import ChoreSplit

@Suite("Rating flow")
@MainActor
struct RatingFlowTests {

    private func makeFlat() throws -> TestHousehold {
        try TestHousehold(choreSpecs: [("Scrub the bathroom", 4, 4, 30), ("Take the bins out", 1, 2, 5)])
    }

    @Test("Finishing a chore doesn't bank the points until peers have rated")
    func completionWaitsOnReview() throws {
        let flat = try makeFlat()
        let assignment = flat.assign(flat.chores[0], to: flat.members[0])

        HouseholdActions.markComplete(assignment, in: flat.household, context: flat.context)

        #expect(assignment.status == .awaitingReview)
        #expect(assignment.awardedPoints == nil)
        #expect(assignment.pointsAreProvisional)
    }

    @Test("Once everyone has rated, the points settle straight away")
    func settlesWhenAllRatersAreIn() throws {
        let flat = try makeFlat()
        let assignment = flat.assign(flat.chores[0], to: flat.members[0])
        HouseholdActions.markComplete(assignment, in: flat.household, context: flat.context)

        for rater in [flat.members[1], flat.members[2]] {
            HouseholdActions.submitQualityRating(
                for: assignment, by: rater, score: 5, in: flat.household, context: flat.context
            )
        }

        #expect(assignment.status == .settled)
        let awarded = try #require(assignment.awardedPoints)
        #expect(awarded > Double(assignment.pointsQuoted))
    }

    @Test("Sloppy work pays less than the chore is worth")
    func poorQualityReducesPayout() throws {
        let flat = try makeFlat()
        let assignment = flat.assign(flat.chores[0], to: flat.members[0])
        HouseholdActions.markComplete(assignment, in: flat.household, context: flat.context)

        for rater in [flat.members[1], flat.members[2]] {
            HouseholdActions.submitQualityRating(
                for: assignment, by: rater, score: 1, in: flat.household, context: flat.context
            )
        }

        let awarded = try #require(assignment.awardedPoints)
        #expect(awarded < Double(assignment.pointsQuoted))
        #expect(awarded > 0)
    }

    @Test("You can't rate the same chore twice")
    func noDoubleRating() throws {
        let flat = try makeFlat()
        let assignment = flat.assign(flat.chores[0], to: flat.members[0])
        HouseholdActions.markComplete(assignment, in: flat.household, context: flat.context)

        HouseholdActions.submitQualityRating(
            for: assignment, by: flat.members[1], score: 5, in: flat.household, context: flat.context
        )
        HouseholdActions.submitQualityRating(
            for: assignment, by: flat.members[1], score: 1, in: flat.household, context: flat.context
        )

        #expect(assignment.ratings.count == 1)
        #expect(assignment.hasRated(flat.members[1]))
    }

    @Test("You're never asked to rate your own work")
    func assigneeIsNotAnEligibleRater() throws {
        let flat = try makeFlat()
        let assignment = flat.assign(flat.chores[0], to: flat.members[0])
        let raters = assignment.eligibleRaters(in: flat.household)
        #expect(!raters.contains { $0.id == flat.members[0].id })
        #expect(raters.count == 2)
    }

    @Test("Scores stay hidden until enough ratings are in")
    func revealThreshold() throws {
        let flat = try makeFlat()
        flat.household.minimumRatingsToReveal = 2
        let assignment = flat.assign(flat.chores[0], to: flat.members[0])
        HouseholdActions.markComplete(assignment, in: flat.household, context: flat.context)

        HouseholdActions.submitQualityRating(
            for: assignment, by: flat.members[1], score: 2, in: flat.household, context: flat.context
        )
        #expect(!assignment.qualityIsRevealed(in: flat.household))

        HouseholdActions.submitQualityRating(
            for: assignment, by: flat.members[2], score: 4, in: flat.household, context: flat.context
        )
        #expect(assignment.qualityIsRevealed(in: flat.household))
    }

    @Test("Anonymous value votes move what a chore is worth")
    func valueVotesRecalibrate() throws {
        let flat = try TestHousehold(choreSpecs: [("Clean the oven", 2, 2, 15)])
        let chore = flat.chores[0]
        let proposed = chore.points

        // Both housemates think it's far worse than advertised.
        for rater in [flat.members[1], flat.members[2]] {
            HouseholdActions.submitValueVote(
                for: chore, by: rater, difficulty: 5, labor: 5, minutes: 60, context: flat.context
            )
        }

        #expect(chore.points > proposed)
        #expect(chore.pointDrift > 0)
        #expect(chore.valuesAreRevealed(in: flat.household))
    }

    @Test("One person can't inflate their own chore")
    func proposerCannotDominate() throws {
        let flat = try TestHousehold(choreSpecs: [("Fluff the cushions", 5, 5, 120)])
        let chore = flat.chores[0]
        let inflated = chore.points

        for rater in [flat.members[1], flat.members[2]] {
            HouseholdActions.submitValueVote(
                for: chore, by: rater, difficulty: 1, labor: 1, minutes: 5, context: flat.context
            )
        }

        // The proposal is one voice among three, so the value drops most of the way back.
        #expect(chore.points < inflated / 2)
    }

    @Test("Voting twice on the same chore is ignored")
    func noDoubleValueVote() throws {
        let flat = try TestHousehold(choreSpecs: [("Vacuum", 2, 3, 25)])
        let chore = flat.chores[0]

        HouseholdActions.submitValueVote(
            for: chore, by: flat.members[1], difficulty: 5, labor: 5, minutes: 90, context: flat.context
        )
        HouseholdActions.submitValueVote(
            for: chore, by: flat.members[1], difficulty: 1, labor: 1, minutes: 5, context: flat.context
        )

        #expect(chore.votes.count == 1)
    }

    @Test("Points quoted at assignment time don't change under the assignee")
    func quotedPointsAreLockedIn() throws {
        let flat = try TestHousehold(choreSpecs: [("Clean the windows", 3, 3, 45)])
        let chore = flat.chores[0]
        let assignment = flat.assign(chore, to: flat.members[0])
        let quoted = assignment.pointsQuoted

        // The household later decides the job is much easier than it looked.
        for rater in [flat.members[1], flat.members[2]] {
            HouseholdActions.submitValueVote(
                for: chore, by: rater, difficulty: 1, labor: 1, minutes: 5, context: flat.context
            )
        }

        #expect(chore.points < quoted)
        #expect(assignment.pointsQuoted == quoted)
    }

    @Test("A skipped chore is worth nothing and stops counting")
    func skippingZeroesTheChore() throws {
        let flat = try makeFlat()
        let assignment = flat.assign(flat.chores[0], to: flat.members[0])
        HouseholdActions.markSkipped(assignment, context: flat.context)

        #expect(assignment.status == .skipped)
        #expect(assignment.effectivePoints == 0)

        let standing = try #require(flat.standing(for: flat.members[0]))
        #expect(standing.load == 0)
    }

    @Test("A solo household settles immediately — there's nobody to rate you")
    func soloHouseholdSettlesAtOnce() throws {
        var flat = try TestHousehold(memberCount: 1, choreSpecs: [("Wash up", 2, 2, 20)])
        let assignment = flat.assign(flat.chores[0], to: flat.members[0])
        HouseholdActions.markComplete(assignment, in: flat.household, context: flat.context)

        #expect(assignment.status == .settled)
        #expect(assignment.awardedPoints == Double(assignment.pointsQuoted))
        _ = flat
    }
}
