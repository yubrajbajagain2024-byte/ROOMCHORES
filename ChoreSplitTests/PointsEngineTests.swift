import Testing
import Foundation
@testable import ChoreSplit

@Suite("Points")
struct PointsEngineTests {

    private func values(_ difficulty: Double, _ labor: Double, _ minutes: Double) -> ChoreValues {
        ChoreValues(difficulty: difficulty, labor: labor, minutes: minutes)
    }

    @Test("A quick bin run is worth far less than a deep clean")
    func spread() {
        let binRun = PointsEngine.points(for: values(1, 2, 5))
        let dishes = PointsEngine.points(for: values(2, 2, 20))
        let deepClean = PointsEngine.points(for: values(4, 4, 45))

        #expect(binRun < dishes)
        #expect(dishes < deepClean)
        // The spread has to be wide enough that people feel the difference, without one
        // chore being worth a whole week of everything else.
        #expect(deepClean < binRun * 10)
    }

    @Test("A chore is never worth nothing")
    func floor() {
        #expect(PointsEngine.points(for: values(1, 1, 5)) >= 1)
        #expect(PointsEngine.points(for: values(0, 0, 0)) >= 1)
    }

    @Test("Unpleasant-but-quick beats long-but-trivial at the same time cost")
    func difficultyCounts() {
        let grim = PointsEngine.points(for: values(5, 4, 15))     // scrubbing the toilet
        let easy = PointsEngine.points(for: values(1, 1, 15))     // wiping a counter
        #expect(grim > easy)
    }

    @Test("Three stars pays face value; one star still pays something")
    func qualityMultiplier() {
        #expect(PointsEngine.qualityMultiplier(averageScore: 3) == 1.0)
        #expect(PointsEngine.qualityMultiplier(averageScore: 1) == 0.6)
        #expect(PointsEngine.qualityMultiplier(averageScore: 5) > 1.0)
        // Bad work is penalised but never zeroed — the job still got done.
        #expect(PointsEngine.qualityMultiplier(averageScore: 1) > 0)
        // And the bonus for excellence stays modest, so the incentive is to do chores
        // rather than to farm compliments.
        #expect(PointsEngine.qualityMultiplier(averageScore: 5) <= 1.25)
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

    @Test("No ratings means face value — silence isn't criticism")
    func unratedPaysFaceValue() {
        #expect(PointsEngine.settledPoints(quoted: 12, averageQuality: nil) == 12)
    }

    @Test("Out-of-range scores are clamped rather than trusted")
    func clamping() {
        #expect(PointsEngine.qualityMultiplier(averageScore: 99) == PointsEngine.qualityMultiplier(averageScore: 5))
        #expect(PointsEngine.qualityMultiplier(averageScore: -4) == PointsEngine.qualityMultiplier(averageScore: 1))
    }
}

@Suite("Spoken reminders")
struct ReminderPhraseTests {

    @Test("Numbers are spelled out so speech doesn't read them as a time")
    func spellsNumbers() {
        #expect(ReminderPhrase.spellOut(4) == "four")
        #expect(ReminderPhrase.spellOut(11) == "eleven")
    }
}
