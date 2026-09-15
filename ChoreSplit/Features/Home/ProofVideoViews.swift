import SwiftUI
import AVKit
import CoreTransferable
import UniformTypeIdentifiers

// MARK: - Thumbnail

/// A still of the proof video with a play button. Tapping plays it full screen — playing
/// inline would mean several videos loading at once as the feed scrolls.
struct ProofVideoThumbnail: View {
    let url: URL
    var duration: Double?
    var height: CGFloat = 320

    @State private var image: UIImage?
    @State private var isPlaying = false

    var body: some View {
        Button {
            isPlaying = true
        } label: {
            Color.black
                .overlay {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ProgressView().tint(.white)
                    }
                }
                .overlay {
                    Image(systemName: "play.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(Circle().fill(.black.opacity(0.45)))
                }
                .overlay(alignment: .bottomLeading) {
                    if let duration {
                        Label(ProofVideoStore.formatDuration(duration), systemImage: "video.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(.black.opacity(0.55)))
                            .padding(10)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .clipped()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Play video\(duration.map { ", \(ProofVideoStore.formatDuration($0))" } ?? "")")
        .task(id: url) {
            image = await ProofVideoStore.thumbnail(for: url)
        }
        .fullScreenCover(isPresented: $isPlaying) {
            VideoPlayerScreen(url: url)
        }
    }
}

// MARK: - Remote video

/// A proof video that's only on the server — someone else's, recorded on their phone. Asks for
/// a short-lived private link, then shows it like any other.
struct RemoteProofVideo: View {
    @Environment(SyncEngine.self) private var sync: SyncEngine?
    let path: String
    var duration: Double?

    @State private var url: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let url {
                ProofVideoThumbnail(url: url, duration: duration)
            } else {
                Color.black
                    .overlay {
                        if failed {
                            Label("Video unavailable offline", systemImage: "wifi.slash")
                                .font(.system(size: 14))
                                .foregroundStyle(.white.opacity(0.8))
                        } else {
                            ProgressView().tint(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 320)
            }
        }
        .task(id: path) {
            guard let sync else { failed = true; return }
            url = await sync.playableVideoURL(path: path)
            failed = url == nil
        }
    }
}

// MARK: - Player

struct VideoPlayerScreen: View {
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            VideoPlayer(player: player)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.black.opacity(0.5)))
            }
            .padding(16)
            .accessibilityLabel("Close video")
        }
        .onAppear {
            // Play sound even with the silent switch on — someone chose to watch this.
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            player.play()
        }
        .onDisappear { player.pause() }
    }
}

// MARK: - Recording

/// The system camera, in video mode, capped at the proof video length.
struct VideoRecorder: UIViewControllerRepresentable {
    /// Called with a copy of the recording that the app owns, or `nil` if cancelled.
    let onFinish: (URL?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && (UIImagePickerController.availableMediaTypes(for: .camera) ?? []).contains(UTType.movie.identifier)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.movie.identifier]
        picker.cameraCaptureMode = .video
        picker.videoQuality = .typeMedium
        picker.videoMaximumDuration = ProofVideoStore.maximumSeconds
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (URL?) -> Void

        init(onFinish: @escaping (URL?) -> Void) {
            self.onFinish = onFinish
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            // The system deletes its own file as soon as this returns, so copy it first.
            guard let recorded = info[.mediaURL] as? URL else {
                onFinish(nil)
                return
            }
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("recorded-\(UUID().uuidString).\(recorded.pathExtension)")
            do {
                try FileManager.default.copyItem(at: recorded, to: copy)
                onFinish(copy)
            } catch {
                onFinish(nil)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

// MARK: - Choosing from Photos

/// A video brought in from the photo library, copied somewhere the app controls.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("picked-\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}
