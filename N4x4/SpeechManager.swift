// SpeechManager.swift
// Wraps AVSpeechSynthesizer for interval voice prompts, and owns the app's
// audio-session choreography:
//   • Ducking — background music lowers while a prompt speaks, then restores.
//   • Workout keepalive — while a workout runs, a looped silent player keeps
//     the audio session (and therefore the app) alive with the phone locked,
//     so the 1 Hz timer keeps ticking and cues fire on time. Requires the
//     "audio" UIBackgroundModes entry. Zero-volume + .mixWithOthers means the
//     user's music is untouched between cues.

import AVFoundation

// @unchecked Sendable: the required `shared` singleton forces Sendability, but
// AVSpeechSynthesizer isn't Sendable. All access happens on the main thread
// (speak/stop are called from the main-actor view model, and the delegate
// callbacks are delivered on the main queue), so this is safe in practice.
final class SpeechManager: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    /// Loops inaudible silence during a workout so iOS never suspends the app
    /// while the phone is locked. Created lazily on first workout start.
    private var keepalivePlayer: AVAudioPlayer?
    private(set) var workoutAudioActive = false

    private override init() {
        super.init()
        synthesizer.delegate = self
        // Resume the keepalive after phone calls / Siri end; without this one
        // interruption would silently kill cues for the rest of the workout.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
    }

    // MARK: - Workout keepalive

    /// Call when a workout starts or resumes. Idempotent.
    func beginWorkoutAudio() {
        guard !workoutAudioActive else { return }
        workoutAudioActive = true
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if keepalivePlayer == nil {
            keepalivePlayer = Self.makeSilentLoopPlayer()
        }
        keepalivePlayer?.play()
    }

    /// Call when the workout pauses, finishes, or resets. Safe to call while a
    /// final utterance (e.g. "Workout complete") is still speaking — session
    /// teardown then happens in the didFinish callback instead.
    func endWorkoutAudio() {
        guard workoutAudioActive else { return }
        workoutAudioActive = false
        keepalivePlayer?.pause()
        if !synthesizer.isSpeaking {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
        }
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard workoutAudioActive,
              let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        keepalivePlayer?.play()
    }

    /// One second of 16-bit mono silence at 8 kHz, generated in memory (no
    /// bundled asset), looped forever at volume 0.
    private static func makeSilentLoopPlayer() -> AVAudioPlayer? {
        let sampleRate: UInt32 = 8000
        let sampleCount = Int(sampleRate)          // 1 s
        let dataSize = UInt32(sampleCount * 2)     // 16-bit mono

        var wav = Data()
        func chunk(_ tag: String) { wav.append(contentsOf: Array(tag.utf8)) }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { wav.append(contentsOf: $0) } }

        chunk("RIFF"); u32(36 + dataSize); chunk("WAVE")
        chunk("fmt "); u32(16); u16(1); u16(1)                 // PCM, mono
        u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)  // rates, align, depth
        chunk("data"); u32(dataSize)
        wav.append(Data(count: sampleCount * 2))               // zero samples

        guard let player = try? AVAudioPlayer(data: wav, fileTypeHint: AVFileType.wav.rawValue)
        else { return nil }
        player.numberOfLoops = -1
        player.volume = 0
        return player
    }

    // MARK: - Speech

    /// Speak a string. Cancels any in-flight speech first.
    /// Ducks background audio (e.g. music) for the duration of the utterance.
    func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        // Duck other audio (music lowers ~30%) while we speak.
        // .voicePrompt mode (iOS 12+) signals a short spoken cue to the system,
        // which produces subtler ducking and faster music recovery than .default.
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .voicePrompt,
            options: [.duckOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.52           // slightly slower than default for workout clarity
        utterance.pitchMultiplier = 1.0
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    /// Stop any in-flight speech immediately (e.g. on pause or reset).
    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    /// Restore the audio session once speech finishes so music returns to full volume.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                            didFinish utterance: AVSpeechUtterance) {
        restoreAudioSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                            didCancel utterance: AVSpeechUtterance) {
        restoreAudioSession()
    }

    private func restoreAudioSession() {
        if workoutAudioActive {
            // Mid-workout: lift the duck WITHOUT abandoning the session — the
            // keepalive must survive or the app suspends on the next lock.
            // A brief pause → deactivate(notify) → reactivate cycle is the
            // deterministic way to make other apps return to full volume.
            keepalivePlayer?.pause()
            try? AVAudioSession.sharedInstance().setActive(
                false, options: .notifyOthersOnDeactivation)
            try? AVAudioSession.sharedInstance().setCategory(
                .playback, options: [.mixWithOthers])
            try? AVAudioSession.sharedInstance().setActive(true)
            keepalivePlayer?.play()
        } else {
            try? AVAudioSession.sharedInstance().setCategory(
                .playback,
                options: [.mixWithOthers]
            )
            // Notify other apps (e.g. Music) that they can return to full volume.
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
        }
    }
}
