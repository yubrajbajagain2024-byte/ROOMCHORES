#if DEBUG
import Foundation
import AVFoundation
import UIKit

/// Writes a short silent clip — a coloured background with a sweeping tick — so the proof
/// video pipeline can be exercised in the demo household and in tests, neither of which has
/// a camera.
enum DemoVideo {

    enum DemoVideoError: Error { case writerFailed }

    static func make(
        seconds: Int,
        framesPerSecond: Int32 = 10,
        size: CGSize = CGSize(width: 360, height: 640),
        color: UIColor
    ) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("demo-\(UUID().uuidString).mp4")
        let width = Int(size.width), height = Int(size.height)

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? DemoVideoError.writerFailed }
        writer.startSession(atSourceTime: .zero)

        let frameCount = seconds * Int(framesPerSecond)
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            guard let pool = adaptor.pixelBufferPool else { throw DemoVideoError.writerFailed }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let buffer else { throw DemoVideoError.writerFailed }

            draw(into: buffer, progress: Double(frame) / Double(max(1, frameCount - 1)), color: color)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: framesPerSecond))
        }

        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? DemoVideoError.writerFailed }
        return url
    }

    private static func draw(into buffer: CVPixelBuffer, progress: Double, color: UIColor) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        let w = CGFloat(width), h = CGFloat(height)
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: w, height: h))

        // A ring that fills as the clip plays, with a tick that appears at the end.
        let radius = min(w, h) * 0.28
        let center = CGPoint(x: w / 2, y: h / 2)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.3).cgColor)
        context.setLineWidth(radius * 0.16)
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        context.strokePath()

        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineCap(.round)
        context.addArc(center: center, radius: radius, startAngle: .pi / 2,
                       endAngle: .pi / 2 - .pi * 2 * CGFloat(progress), clockwise: true)
        context.strokePath()

        if progress > 0.6 {
            context.setLineWidth(radius * 0.14)
            context.setLineJoin(.round)
            context.move(to: CGPoint(x: center.x - radius * 0.42, y: center.y))
            context.addLine(to: CGPoint(x: center.x - radius * 0.1, y: center.y - radius * 0.32))
            context.addLine(to: CGPoint(x: center.x + radius * 0.45, y: center.y + radius * 0.35))
            context.strokePath()
        }
    }
}
#endif
