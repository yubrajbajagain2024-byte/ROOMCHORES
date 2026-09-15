import Foundation
import SwiftData
import UIKit

/// A fully populated household, for trying the app out without spending ten minutes on
/// setup first. Available from the first setup screen in debug builds.
enum DemoData {

    static func populate(_ household: Household, context: ModelContext) {
        household.name = "Flat 3B"
        household.cycleLengthDays = 7
        household.cycleStartDate = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        household.setupStage = .running

        let people: [(String, String)] = [("Alex Kerr", "🦊"), ("Priya Shah", "🌻"), ("Sam Okafor", "🎧")]
        var members: [Roommate] = []
        for (index, person) in people.enumerated() {
            let member = Roommate(name: person.0, emoji: person.1, paletteIndex: index)
            member.household = household
            context.insert(member)
            members.append(member)
        }

        // Each person proposes a few chores, as they would during setup.
        let proposals: [(Int, String)] = [
            (0, "Wash up after dinner"), (0, "Take the bins out"), (0, "Clean the shower and bath"),
            (1, "Vacuum the living room"), (1, "Scrub the toilet"), (1, "Do the household grocery run"),
            (2, "Mop the kitchen floor"), (2, "Sort the recycling"), (2, "Clean out the fridge")
        ]
        var chores: [Chore] = []
        for (memberIndex, title) in proposals {
            guard let starter = StarterChores.all.first(where: { $0.title == title }) else { continue }
            let chore = Chore(
                title: starter.title,
                category: starter.category,
                recurrence: starter.recurrence,
                difficulty: starter.difficulty,
                labor: starter.labor,
                minutes: starter.minutes,
                proposerID: members[memberIndex].id
            )
            chore.household = household
            context.insert(chore)
            chores.append(chore)
        }

        // Everyone rates everyone else's chores, drifting a little either way so the
        // proposed-vs-agreed comparison has something to show.
        // The last chore is deliberately left unrated by the first roommate, so the
        // "what is this worth?" queue has something in it on first open.
        for (choreIndex, chore) in chores.enumerated() {
            for member in members where member.id != chore.proposerID {
                if choreIndex == chores.count - 1 && member.id == members[0].id { continue }
                let drift = Int.random(in: -1...1)
                HouseholdActions.submitValueVote(
                    for: chore,
                    by: member,
                    difficulty: clamp(chore.proposedDifficulty + drift),
                    labor: clamp(chore.proposedLabor + Int.random(in: -1...1)),
                    minutes: max(5, chore.proposedMinutes + Int.random(in: -2...3) * 5),
                    context: context
                )
            }
        }

        // A few days of history, deliberately lopsided so the catch-up rule has something
        // to react to: Alex has done most of it, Sam almost none.
        let completions: [(Int, Int, Int)] = [   // (member index, chore index, days ago)
            (0, 0, 3), (0, 1, 3), (0, 3, 2), (0, 4, 1),
            (1, 2, 2), (1, 5, 1),
            (2, 7, 2)
        ]
        for (memberIndex, choreIndex, daysAgo) in completions {
            guard choreIndex < chores.count else { continue }
            let due = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
            let assignment = Assignment(chore: chores[choreIndex], assignee: members[memberIndex], dueDate: due)
            assignment.household = household
            assignment.assignedAt = due
            assignment.completedAt = due
            context.insert(assignment)

            for rater in members where rater.id != members[memberIndex].id {
                HouseholdActions.submitQualityRating(
                    for: assignment,
                    by: rater,
                    score: Int.random(in: 3...5),
                    in: household,
                    context: context
                )
            }
            HouseholdActions.settle(assignment)
        }

        // Open work for the days ahead.
        for (index, chore) in chores.enumerated() where index % 3 == 0 {
            guard let next = FairnessEngine.nextInLine(for: household) else { break }
            HouseholdActions.assign(
                chore: chore,
                to: next,
                due: FairnessEngine.defaultDueDate(for: chore, in: household),
                in: household,
                context: context,
                autoAssigned: true,
                reason: "Lowest points in the household",
                scheduleReminder: false
            )
        }

        // A to-do list for the first roommate, so the home screen has something on it.
        let myTasks = FairnessEngine.availableChores(in: household).prefix(3)
        for (offset, chore) in myTasks.enumerated() {
            let due = Calendar.current.date(
                bySettingHour: 20, minute: 0, second: 0,
                of: Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
            ) ?? Date()
            let assignment = HouseholdActions.assign(
                chore: chore,
                to: members[0],
                due: due,
                in: household,
                context: context,
                reason: "Added by \(members[0].shortName)",
                scheduleReminder: false
            )
            // Leave the last one without a reminder, so both row styles show.
            if offset == myTasks.count - 1 { assignment.reminderDate = nil }
        }

        // Two chores finished but not yet rated: one by the first roommate, so they can
        // see their own points sitting provisional, and one by someone else, so they have
        // a rating waiting for them.
        let pending: [(Int, Int)] = [(0, 1), (2, 4)]   // (member index, chore index)
        var awaitingReview: [Assignment] = []
        for (memberIndex, choreIndex) in pending where choreIndex < chores.count {
            let assignment = Assignment(
                chore: chores[choreIndex],
                assignee: members[memberIndex],
                dueDate: Calendar.current.date(byAdding: .hour, value: -4, to: Date()) ?? Date()
            )
            assignment.household = household
            assignment.completedAt = Calendar.current.date(byAdding: .hour, value: -2, to: Date())
            assignment.status = .awaitingReview
            context.insert(assignment)
            awaitingReview.append(assignment)
        }

        try? context.save()

        #if DEBUG
        // Finished tasks come with a proof video, like real ones do. The clips are generated,
        // so this runs after the household is already usable.
        let colors: [UIColor] = [.systemTeal, .systemOrange, .systemIndigo]
        Task { @MainActor in
            for (index, assignment) in awaitingReview.enumerated() {
                guard let clip = try? await DemoVideo.make(seconds: 5 + index * 3, color: colors[index % colors.count]),
                      let prepared = try? await ProofVideoStore.prepare(from: clip)
                else { continue }
                try? FileManager.default.removeItem(at: clip)
                assignment.proofVideoFilename = try? ProofVideoStore.commit(prepared, for: assignment.id)
                assignment.proofVideoDuration = prepared.duration
                try? context.save()
            }
        }
        #endif
    }

    private static func clamp(_ value: Int) -> Int { min(5, max(1, value)) }
}
