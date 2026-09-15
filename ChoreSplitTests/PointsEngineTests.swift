import Testing
import Foundation
@testable import ChoreSplit

@Suite("Points")
struct PointsEngineTests {

    private func values(_ difficulty: Double, _ labor: Double, _ minutes: Double) -> ChoreValues {
        ChoreValues(difficulty: difficulty, labor: labor, minutes: minutes)
    }

    @Test("Every possible chore is worth between 1 and 4 points")
    func alwaysOnTheScale() {
        for difficulty in 1...5 {
            for labor in 1...5 {
                for minutes in stride(from: 5, through: 120, by: 5) {
                    let points = PointsEngine.points(for: values(Double(difficulty), Double(labor), Double(minutes)))
                    #expect(PointsEngine.pointRange.contains(points), "\(difficulty)/\(labor)/\(minutes)min gave \(points)")
                }
            }
        }
    }

    @Test("Out-of-range inputs still land on the scale")
    func clampsWildInputs() {
        #expect(PointsEngine.points(for: values(0, 0, 0)) == 1)
        #expect(PointsEngine.points(for: values(99, 99, 9_999)) == 4)
        #expect(PointsEngine.points(for: values(-3, -3, -10)) == 1)
    }

    @Test("The easiest job is 1 point and the biggest is 4")
    func endsOfTheScale() {
        #expect(PointsEngine.points(for: values(1, 1, 5)) == 1)
        #expect(PointsEngine.points(for: values(5, 5, 90)) == 4)
    }

    @Test("A quick bin run is worth less than washing up, which is worth less than a deep clean")
    func ordering() {
        let binRun = PointsEngine.points(for: values(1, 2, 5))
        let dishes = PointsEngine.points(for: values(2, 2, 20))
        let deepClean = PointsEngine.points(for: values(4, 4, 45))
        #expect(binRun < dishes)
        #expect(dishes < deepClean)
    }

    @Test("Unpleasant-but-quick beats trivial at the same time cost")
    func difficultyCounts() {
        let grim = PointsEngine.points(for: values(5, 4, 15))     // scrubbing the toilet
        let easy = PointsEngine.points(for: values(1, 1, 15))     // wiping a counter
        #expect(grim > easy)
    }

    @Test("More of any one factor never makes a chore worth less")
    func monotonicInEveryInput() {
        for base in [1.0, 3.0] {
            let reference = PointsEngine.exactScore(for: values(base, base, 15))
            #expect(PointsEngine.exactScore(for: values(base + 1, base, 15)) >= reference)
            #expect(PointsEngine.exactScore(for: values(base, base + 1, 15)) >= reference)
            #expect(PointsEngine.exactScore(for: values(base, base, 60)) >= reference)
        }
    }

    @Test("Time is banded, so a few minutes either way doesn't change the level")
    func timeBands() {
        #expect(PointsEngine.level(forMinutes: 5) == 1)
        #expect(PointsEngine.level(forMinutes: 10) == 1)
        #expect(PointsEngine.level(forMinutes: 15) == 2)
        #expect(PointsEngine.level(forMinutes: 20) == 2)
        #expect(PointsEngine.level(forMinutes: 30) == 3)
        #expect(PointsEngine.level(forMinutes: 45) == 4)
    }

    @Test("The starter chore library uses the whole scale")
    func starterLibrarySpread() {
        let used = Set(StarterChores.all.map {
            PointsEngine.points(for: values(Double($0.difficulty), Double($0.labor), Double($0.minutes)))
        })
        #expect(used == Set(PointsEngine.pointRange))
    }

    // MARK: Quality

    @Test("Three stars or more pays full points; one star pays half")
    func qualityMultiplier() {
        #expect(PointsEngine.qualityMultiplier(averageScore: 1) == 0.5)
        #expect(PointsEngine.qualityMultiplier(averageScore: 2) == 0.75)
        #expect(PointsEngine.qualityMultiplier(averageScore: 3) == 1.0)
        #expect(PointsEngine.qualityMultiplier(averageScore: 5) == 1.0)
    }

    @Test("A payout never goes above the chore's points")
    func noBonusAboveTheScale() {
        for quoted in PointsEngine.pointRange {
            for stars in stride(from: 1.0, through: 5.0, by: 0.5) {
                let paid = PointsEngine.settledPoints(quoted: quoted, averageQuality: stars)
                #expect(paid <= Double(quoted))
                #expect(paid > 0)
            }
        }
    }

    @Test("Payouts come in half-point steps")
    func halfPointSteps() {
        for quoted in PointsEngine.pointRange {
            for stars in stride(from: 1.0, through: 5.0, by: 0.25) {
                let paid = PointsEngine.settledPoints(quoted: quoted, averageQuality: stars)
                #expect((paid * 2).rounded() == paid * 2)
            }
        }
    }

    @Test("The multiplier rises monotonically with the score")
    func qualityIsMonotonic() {
        var previous = 0.0
        for step in stride(from: 1.0, through: 5.0, by: 0.25) {
            let value = PointsEngine.qualityMultiplier(averageScore: step)
            #expect(value >= previous)
            previous = value
        }
    }

    @Test("No ratings means full points — silence isn't criticism")
    func unratedPaysFullPoints() {
        #expect(PointsEngine.settledPoints(quoted: 3, averageQuality: nil) == 3)
    }

    @Test("Out-of-range scores are clamped rather than trusted")
    func clamping() {
        #expect(PointsEngine.qualityMultiplier(averageScore: 99) == PointsEngine.qualityMultiplier(averageScore: 5))
        #expect(PointsEngine.qualityMultiplier(averageScore: -4) == PointsEngine.qualityMultiplier(averageScore: 1))
    }

    @Test("Points display without a trailing .0")
    func formatting() {
        #expect(PointsEngine.format(3) == "3")
        #expect(PointsEngine.format(2.5) == "2.5")
        #expect(PointsEngine.format(1.26) == "1.5")
    }
}

@Suite("Spoken reminders")
struct ReminderPhraseTests {

    @Test("Numbers are spelled out so speech doesn't read them as a time")
    func spellsNumbers() {
        #expect(ReminderPhrase.spellOut(4) == "four")
        #expect(ReminderPhrase.spellOut(1) == "one")
    }

    @Test("One point is singular")
    func singularPoint() {
        let sentence = ReminderPhrase.sentence(assigneeName: "Sam Okafor", choreTitle: "Water the plants", points: 1, dueDate: Date())
        #expect(sentence.hasSuffix("That's one point."))
        #expect(sentence.hasPrefix("Sam,"))
    }
}

@Suite("Add task defaults")
struct AddTaskDefaultsTests {

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }

    @Test("A new task is due tonight when there's time, otherwise tomorrow night")
    func dueDate() {
        let afternoon = date(15)
        #expect(Calendar.current.isDate(AddTaskSheet.defaultDueDate(now: afternoon), inSameDayAs: afternoon))

        let lateEvening = date(19, 30)
        let due = AddTaskSheet.defaultDueDate(now: lateEvening)
        #expect(due.timeIntervalSince(lateEvening) >= 3600)
    }

    @Test("The suggested reminder is before the due time and never in the past")
    func reminder() {
        let now = date(12)
        let due = date(20)
        let suggested = AddTaskSheet.suggestedReminder(forDue: due, now: now)
        #expect(suggested > now)
        #expect(suggested <= due)
        #expect(suggested == due.addingTimeInterval(-7200))
    }

    @Test("With the due time close, the reminder moves closer rather than into the past")
    func reminderWhenDueSoon() {
        let now = date(19, 20)
        let due = date(20)
        let suggested = AddTaskSheet.suggestedReminder(forDue: due, now: now)
        #expect(suggested > now)
        #expect(suggested <= due)
    }
}
