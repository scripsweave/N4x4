// N4x4WatchApp.swift
// watchOS app entry point.
//
// If Xcode generated a default N4x4WatchApp.swift when the target was added,
// replace its contents entirely with this file.

import SwiftUI

@main
struct N4x4WatchApp: App {

    @StateObject private var sessionManager = WatchSessionManager()
    @StateObject private var workoutManager = WorkoutManager()

    var body: some Scene {
        WindowGroup {
            WatchTimerView()
                .environmentObject(sessionManager)
                .environmentObject(workoutManager)
                .onAppear {
                    sessionManager.activate()
                    workoutManager.requestAuthorization { _ in }
                    workoutManager.discardAbandonedSession()
                }
        }
    }
}
