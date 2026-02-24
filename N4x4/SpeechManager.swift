// SpeechManager.swift
// Wraps AVSpeechSynthesizer for interval voice prompts.
// Handles audio session ducking so background music lowers while speaking,
// then restores automatically when speech finishes.

import AVFoundation

class SpeechManager: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

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
