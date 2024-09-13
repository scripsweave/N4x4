//
//  AudioManager.swift
//  N4x4
//
//  Created by Jan van Rensburg on 9/12/24.
//
// AudioManager.swift

import AVFoundation

class AudioManager {
    static let shared = AudioManager()
    var player: AVAudioPlayer?

    private init() {}

    func playAlarm() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("Error playing alarm sound: \(error.localizedDescription)")
        }
    }
}
