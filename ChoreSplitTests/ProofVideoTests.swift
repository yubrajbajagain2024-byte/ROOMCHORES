import Testing
import Foundation
import SwiftData
import UIKit
@testable import ChoreSplit

@Suite("Proof videos", .serialized)
@MainActor
struct ProofVideoTests {

    @Test("A short clip is converted and kept whole")
    func preparesShortClip() async throws {
        let source = try await DemoVideo.make(seconds: 3, size: CGSize(width: 180, height: 320), color: .systemTeal)
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await ProofVideoStore.prepare(from: source)
        defer { ProofVideoStore.discard(prepared) }

        #expect(FileManager.default.fileExists(atPath: prepared.url.path))
        #expect(prepared.url.pathExtension == "mp4")
        #expect(!prepared.wasTrimmed)
        #expect(abs(prepared.duration - 3) < 0.5)
        // The original is left for the caller to clean up.
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("Anything over a minute is trimmed to the first minute")
    func trimsLongClip() async throws {
        let source = try await DemoVideo.make(seconds: 70, framesPerSecond: 1, size: CGSize(width: 64, height: 64), color: .systemOrange)
        defer { try? FileManager.default.removeItem(at: source) }

        let prepared = try await ProofVideoStore.prepare(from: source)
        defer { ProofVideoStore.discard(prepared) }

        #expect(prepared.wasTrimmed)
        #expect(prepared.duration <= ProofVideoStore.maximumSeconds + 1)
    }

    @Test("Something that isn't a video is rejected")
    func rejectsNonVideo() async throws {
        let bogus = FileManager.default.temporaryDirectory.appendingPathComponent("not-a-video-\(UUID().uuidString).mp4")
        try Data("hello".utf8).write(to: bogus)
        defer { try? FileManager.default.removeItem(at: bogus) }

        await #expect(throws: ProofVideoStore.StoreError.self) {
            _ = try await ProofVideoStore.prepare(from: bogus)
        }
    }

    @Test("A stored video has a thumbnail")
    func thumbnail() async throws {
        let source = try await DemoVideo.make(seconds: 2, size: CGSize(width: 180, height: 320), color: .systemIndigo)
        defer { try? FileManager.default.removeItem(at: source) }

        let image = await ProofVideoStore.thumbnail(for: source)
        let size = try #require(image?.size)
        #expect(size.height > size.width)   // portrait clips stay portrait
    }

    @Test("Ratings closing deletes the video; until then it stays attached")
    func videoLivesUntilRatingsClose() async throws {
        let flat = try TestHousehold(choreSpecs: [("Scrub the toilet", 4, 3, 15)])
        let task = flat.assign(flat.chores[0], to: flat.members[0])

        let source = try await DemoVideo.make(seconds: 2, size: CGSize(width: 180, height: 320), color: .systemPink)
        defer { try? FileManager.default.removeItem(at: source) }
        let prepared = try await ProofVideoStore.prepare(from: source)

        task.proofVideoFilename = try ProofVideoStore.commit(prepared, for: task.id)
        task.proofVideoDuration = prepared.duration
        HouseholdActions.markComplete(task, in: flat.household, context: flat.context)

        let stored = try #require(task.proofVideoURL)
        #expect(!FileManager.default.fileExists(atPath: prepared.url.path))   // moved, not copied

        // One rating in: still being rated, video still there for the other roommate.
        HouseholdActions.submitQualityRating(for: task, by: flat.members[1], score: 4, in: flat.household, context: flat.context)
        #expect(task.status == .awaitingReview)
        #expect(FileManager.default.fileExists(atPath: stored.path))

        // Last rating in: points settle and the video goes.
        HouseholdActions.submitQualityRating(for: task, by: flat.members[2], score: 5, in: flat.household, context: flat.context)
        #expect(task.status == .settled)
        #expect(task.proofVideoFilename == nil)
        #expect(!FileManager.default.fileExists(atPath: stored.path))
    }

    @Test("Durations read like a video player's")
    func durationFormatting() {
        #expect(ProofVideoStore.formatDuration(5) == "0:05")
        #expect(ProofVideoStore.formatDuration(59.6) == "1:00")
        #expect(ProofVideoStore.formatDuration(83) == "1:23")
    }
}
