import Foundation
import AVFoundation

/// Speaks reminders out loud, and — the harder half — makes a scheduled reminder speak
/// even when the app is closed.
///
/// iOS will not run text-to-speech from a notification, so instead the sentence is
/// synthesised to an audio file ahead of time and handed to the notification as its
/// custom sound. When the reminder fires, the phone says "Sam, the kitchen bins are due
/// tonight, that's four points" rather than playing a generic chime.
///
/// Constraints that shape this code: notification sounds must live in `Library/Sounds`,
/// be under 30 seconds, and be CAF/AIFF/WAV.
final class VoiceReminderService {

    static let shared = VoiceReminderService()

    /// Held as a property because a synthesiser deallocated mid-utterance stops speaking.
    private let liveSynthesizer = AVSpeechSynthesizer()
    private var renderingSynthesizer: AVSpeechSynthesizer?

    /// iOS refuses notification sounds of 30 seconds or more.
    private static let maximumSoundSeconds: Double = 29

    private init() {}

    // MARK: - Speaking in the app

    /// Speak immediately — used for the preview button and for tapping a reminder.
    func speak(_ text: String, rate: Float = 0.5) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        configureAudioSession()
        if liveSynthesizer.isSpeaking {
            liveSynthesizer.stopSpeaking(at: .immediate)
        }
        liveSynthesizer.speak(utterance(for: text, rate: rate))
    }

    func stopSpeaking() {
        liveSynthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool { liveSynthesizer.isSpeaking }

    // MARK: - Rendering a notification sound

    /// Synthesise `text` to a CAF file in `Library/Sounds` and return its filename,
    /// ready to be used as `UNNotificationSound(named:)`. Returns `nil` if synthesis
    /// fails, in which case the caller falls back to the default notification sound.
    @discardableResult
    func renderSoundFile(for text: String, identifier: String, rate: Float = 0.5) async -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Keep well inside the 30-second ceiling; speech runs ~13 characters a second.
        let capped = String(trimmed.prefix(320))
        let filename = "reminder-\(identifier).caf"

        guard let soundsDirectory = Self.soundsDirectory() else { return nil }
        let url = soundsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)

        let synthesizer = AVSpeechSynthesizer()
        renderingSynthesizer = synthesizer

        let succeeded: Bool = await withCheckedContinuation { continuation in
            var audioFile: AVAudioFile?
            var didFinish = false
            var wroteAnyAudio = false

            synthesizer.write(utterance(for: capped, rate: rate)) { buffer in
                guard !didFinish else { return }
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer else { return }

                // A zero-length buffer marks the end of the utterance.
                guard pcmBuffer.frameLength > 0 else {
                    didFinish = true
                    audioFile = nil
                    continuation.resume(returning: wroteAnyAudio)
                    return
                }

                do {
                    if audioFile == nil {
                        // The synthesiser hands back 32-bit float buffers, but notification
                        // sounds have to be 16-bit linear PCM. Declaring the *file* as Int16
                        // while keeping the *processing* format as the synthesiser's own lets
                        // AVAudioFile convert on the way out.
                        let fileSettings: [String: Any] = [
                            AVFormatIDKey: kAudioFormatLinearPCM,
                            AVSampleRateKey: pcmBuffer.format.sampleRate,
                            AVNumberOfChannelsKey: pcmBuffer.format.channelCount,
                            AVLinearPCMBitDepthKey: 16,
                            AVLinearPCMIsFloatKey: false,
                            AVLinearPCMIsBigEndianKey: false,
                            AVLinearPCMIsNonInterleaved: false
                        ]
                        audioFile = try AVAudioFile(
                            forWriting: url,
                            settings: fileSettings,
                            commonFormat: pcmBuffer.format.commonFormat,
                            interleaved: pcmBuffer.format.isInterleaved
                        )
                    }
                    try audioFile?.write(from: pcmBuffer)
                    wroteAnyAudio = true
                } catch {
                    didFinish = true
                    audioFile = nil
                    continuation.resume(returning: false)
                }
            }
        }

        renderingSynthesizer = nil

        guard succeeded, FileManager.default.fileExists(atPath: url.path) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }

        // iOS silently falls back to the default sound for anything 30 seconds or longer,
        // which would look like the voice reminder simply not working. Check rather than hope.
        if let file = try? AVAudioFile(forReading: url), file.fileFormat.sampleRate > 0 {
            let seconds = Double(file.length) / file.fileFormat.sampleRate
            guard seconds < Self.maximumSoundSeconds else {
                try? FileManager.default.removeItem(at: url)
                return nil
            }
        }
        return filename
    }

    /// Remove a rendered sound once its reminder is gone, so the folder does not grow
    /// a file per chore forever.
    func deleteSoundFile(named filename: String) {
        guard let directory = Self.soundsDirectory() else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    /// Drop any rendered sounds no longer referenced by a scheduled reminder.
    func pruneSoundFiles(keeping keepFilenames: Set<String>) {
        guard let directory = Self.soundsDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }
        for file in files where file.hasPrefix("reminder-") && !keepFilenames.contains(file) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(file))
        }
    }

    // MARK: - Voices

    /// Voices matching the device language, best quality first. Enhanced and premium
    /// voices only exist once the user has downloaded them in iOS Settings.
    static var availableVoices: [AVSpeechSynthesisVoice] {
        let languagePrefix = String(AVSpeechSynthesisVoice.currentLanguageCode().prefix(2))
        let matching = AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(languagePrefix) }
        let ordered = matching.sorted { lhs, rhs in
            if lhs.quality.rawValue != rhs.quality.rawValue {
                return lhs.quality.rawValue > rhs.quality.rawValue
            }
            return lhs.name < rhs.name
        }
        return ordered.isEmpty ? AVSpeechSynthesisVoice.speechVoices() : ordered
    }

    // MARK: - Internals

    private func utterance(for text: String, rate: Float) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0
        if let identifier = VoiceSettings.selectedVoiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        } else if let best = Self.availableVoices.first {
            utterance.voice = best
        }
        return utterance
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        // Duck music rather than stopping it — a chore reminder should not kill the playlist.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true, options: [])
    }

    private static func soundsDirectory() -> URL? {
        guard let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        let sounds = library.appendingPathComponent("Sounds", isDirectory: true)
        if !FileManager.default.fileExists(atPath: sounds.path) {
            try? FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
        }
        return sounds
    }
}

/// Voice preferences, kept in `UserDefaults` because they are device settings rather
/// than household data.
enum VoiceSettings {
    private static let voiceKey = "voice.identifier"
    private static let rateKey = "voice.rate"

    static var selectedVoiceIdentifier: String? {
        get { UserDefaults.standard.string(forKey: voiceKey) }
        set { UserDefaults.standard.set(newValue, forKey: voiceKey) }
    }

    static var rate: Float {
        get {
            let stored = UserDefaults.standard.float(forKey: rateKey)
            return stored == 0 ? AVSpeechUtteranceDefaultSpeechRate : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: rateKey) }
    }
}
