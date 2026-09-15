import Foundation
import AVFoundation
import UIKit

/// A proof video that has been converted and trimmed, waiting to be attached to a task.
struct PreparedVideo: Equatable {
    let url: URL
    let duration: Double
    /// The source was longer than the limit and only the start was kept.
    let wasTrimmed: Bool
}

/// Where the videos that prove a task was done live, from the moment they're picked until
/// ratings close.
///
/// Every clip — recorded or chosen from Photos — goes through the same conversion: re-encoded
/// at medium quality and capped at a minute. A shared phone collecting a video per chore per
/// day would otherwise fill up fast, and a raw 4K clip is far more than anyone needs to see a
/// clean bathroom.
enum ProofVideoStore {

    static let maximumSeconds: Double = 60

    enum StoreError: LocalizedError {
        case unreadable
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .unreadable:   return "That video couldn't be opened."
            case .exportFailed: return "That video couldn't be prepared. Try another one."
            }
        }
    }

    // MARK: - Preparing

    /// Convert and trim a video into a temporary file. The source is left untouched.
    static func prepare(from source: URL) async throws -> PreparedVideo {
        let asset = AVURLAsset(url: source)
        let sourceDuration: Double
        do {
            sourceDuration = try await asset.load(.duration).seconds
        } catch {
            throw StoreError.unreadable
        }
        guard sourceDuration.isFinite, sourceDuration > 0,
              let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetMediumQuality)
        else { throw StoreError.unreadable }

        let wasTrimmed = sourceDuration > maximumSeconds
        let keptDuration = min(sourceDuration, maximumSeconds)
        session.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: keptDuration, preferredTimescale: 600)
        )
        session.shouldOptimizeForNetworkUse = true

        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("proof-\(UUID().uuidString).mp4")
        do {
            try await session.export(to: output, as: .mp4)
        } catch {
            try? FileManager.default.removeItem(at: output)
            throw StoreError.exportFailed
        }

        let finalDuration = (try? await AVURLAsset(url: output).load(.duration).seconds) ?? keptDuration
        return PreparedVideo(url: output, duration: finalDuration, wasTrimmed: wasTrimmed)
    }

    // MARK: - Storing

    /// Move a prepared video into permanent storage for a task, returning the file name to
    /// keep on the assignment.
    static func commit(_ video: PreparedVideo, for assignmentID: UUID) throws -> String {
        let filename = "\(assignmentID.uuidString).mp4"
        let destination = directory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: video.url, to: destination)
        return filename
    }

    static func existingURL(for filename: String) -> URL? {
        let url = directory.appendingPathComponent(filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(filename: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    /// Throw away a prepared video that was never attached.
    static func discard(_ video: PreparedVideo) {
        try? FileManager.default.removeItem(at: video.url)
    }

    /// Delete stored videos that no task is waiting on any more.
    static func prune(keeping filenames: Set<String>) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else { return }
        for file in files where !filenames.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: - Previews

    /// A still from near the start of the clip, the right way up.
    static func thumbnail(for url: URL, maxDimension: CGFloat = 900) async -> UIImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        for seconds in [0.5, 0.0] {
            if let (image, _) = try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)) {
                return UIImage(cgImage: image)
            }
        }
        return nil
    }

    /// "0:23"
    static func formatDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    // MARK: - Location

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let folder = base.appendingPathComponent("ProofVideos", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }
}
