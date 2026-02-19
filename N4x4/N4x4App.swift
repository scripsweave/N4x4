// N4x4App.swift
// N4x4
//
// Created by Jan van Rensburg on 9/12/24.
//

import SwiftUI
import UserNotifications
import AVFoundation  // Import AVFoundation to access AVAudioSession

@main
struct N4x4App: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            TimerView(viewModel: TimerViewModel())
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // Set up the audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Set the category to .ambient or .playback with .mixWithOthers option
            // try audioSession.setCategory(.ambient, options: [.mixWithOthers])
            try audioSession.setCategory(.playback, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set audio session category: \(error.localizedDescription)")
        }

        return true
    }

    // Handle notifications when app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
