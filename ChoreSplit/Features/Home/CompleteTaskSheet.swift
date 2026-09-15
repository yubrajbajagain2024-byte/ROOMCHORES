import SwiftUI
import SwiftData
import PhotosUI

/// Finishing a task means showing it: record a video or pick one, then mark it done. The
/// video is what your roommates watch before they rate the work.
struct CompleteTaskSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let assignment: Assignment
    let household: Household
    var onCompleted: () -> Void = {}

    @State private var video: PreparedVideo?
    @State private var isPreparing = false
    @State private var errorMessage: String?
    @State private var showingRecorder = false
    @State private var pickerItem: PhotosPickerItem?
    /// Set once the video has been handed over to the task, so dismissing doesn't delete it.
    @State private var didComplete = false

    private let cameraAvailable = VideoRecorder.isAvailable

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    taskCard
                    proofCard
                }
                .padding(.bottom, 16)
            }
            .background(Theme.feedBackground)
            .safeAreaInset(edge: .bottom) { doneBar }
            .navigationTitle("Finish task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showingRecorder) {
                VideoRecorder { url in
                    showingRecorder = false
                    if let url { prepare(url) }
                }
                .ignoresSafeArea()
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                importFromPhotos(item)
            }
            .onDisappear {
                if !didComplete, let video { ProofVideoStore.discard(video) }
            }
            .interactiveDismissDisabled(isPreparing)
            #if DEBUG
            // `--attach-demo-video` fills in a generated clip, for checking the attached state
            // in a simulator that has no camera.
            .task {
                guard ProcessInfo.processInfo.arguments.contains("--attach-demo-video"), video == nil else { return }
                if let clip = try? await DemoVideo.make(seconds: 6, color: .systemTeal) { prepare(clip) }
            }
            #endif
        }
    }

    // MARK: - Task

    private var taskCard: some View {
        HStack(spacing: 12) {
            let category = assignment.chore?.category ?? .other
            ZStack {
                Circle().fill(category.tint.opacity(0.15))
                Image(systemName: category.symbol)
                    .foregroundStyle(category.tint)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(assignment.title)
                    .font(.system(size: 18, weight: .bold))
                Text("Worth \(assignment.pointsQuoted) pts · Due \(assignment.dueDescription.lowercased())")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
        }
        .padding(14)
        .background(Theme.feedCard)
    }

    // MARK: - Proof

    private var proofCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            FeedSectionHeader(
                title: "Show it's done",
                subtitle: "Add a video of the finished job. Your roommates watch it before they rate. Up to 1 minute."
            )

            if let video {
                ProofVideoThumbnail(url: video.url, duration: video.duration, height: 380)

                HStack {
                    if video.wasTrimmed {
                        Label("Only the first minute is kept", systemImage: "scissors")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        ProofVideoStore.discard(video)
                        self.video = nil
                    } label: {
                        Label("Remove", systemImage: "trash")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .tint(Theme.rose)
                }
                .padding(.horizontal, 14)
            } else if isPreparing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Preparing video…")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            } else {
                VStack(spacing: 10) {
                    sourceButton(
                        title: "Record a video",
                        systemImage: "video.fill",
                        tint: Theme.rose,
                        enabled: cameraAvailable
                    ) {
                        showingRecorder = true
                    }

                    PhotosPicker(selection: $pickerItem, matching: .videos, preferredItemEncoding: .current) {
                        sourceLabel(title: "Choose from Photos", systemImage: "photo.on.rectangle.angled", tint: Theme.green)
                    }
                    .buttonStyle(.plain)

                    if !cameraAvailable {
                        Text("This device has no camera — choose a video instead.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(.horizontal, 14)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.rose)
                    .padding(.horizontal, 14)
            }
        }
        .padding(.vertical, 14)
        .background(Theme.feedCard)
    }

    private func sourceButton(title: String, systemImage: String, tint: Color, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            sourceLabel(title: title, systemImage: systemImage, tint: tint)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
    }

    private func sourceLabel(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundStyle(tint)
                .frame(width: 28)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.chipFill))
        .contentShape(Rectangle())
    }

    // MARK: - Done

    private var doneBar: some View {
        VStack(spacing: 6) {
            Button(action: markDone) {
                Text("Mark as done")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(video == nil ? Theme.brand.opacity(0.35) : Theme.brand)
                    )
            }
            .buttonStyle(.plain)
            .disabled(video == nil)

            if video == nil {
                Text("Add a video to finish")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(Theme.feedCard.ignoresSafeArea(edges: .bottom))
    }

    // MARK: - Actions

    private func importFromPhotos(_ item: PhotosPickerItem) {
        errorMessage = nil
        isPreparing = true
        Task {
            do {
                guard let movie = try await item.loadTransferable(type: PickedMovie.self) else {
                    throw ProofVideoStore.StoreError.unreadable
                }
                prepare(movie.url)
            } catch {
                isPreparing = false
                errorMessage = "That video couldn't be loaded. Try another one."
            }
            pickerItem = nil
        }
    }

    /// Convert whatever came in, then throw the raw copy away.
    private func prepare(_ source: URL) {
        errorMessage = nil
        isPreparing = true
        Task {
            defer { try? FileManager.default.removeItem(at: source) }
            do {
                let prepared = try await ProofVideoStore.prepare(from: source)
                if let old = video { ProofVideoStore.discard(old) }
                video = prepared
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "That video couldn't be prepared."
            }
            isPreparing = false
        }
    }

    private func markDone() {
        guard let video else { return }
        do {
            assignment.proofVideoFilename = try ProofVideoStore.commit(video, for: assignment.id)
            assignment.proofVideoDuration = video.duration
        } catch {
            errorMessage = "The video couldn't be saved. Try again."
            return
        }
        didComplete = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation {
            HouseholdActions.markComplete(assignment, in: household, context: context)
        }
        onCompleted()
        dismiss()
    }
}
