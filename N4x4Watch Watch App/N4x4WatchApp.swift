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
            WatchRootView()
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

private struct WatchRootView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @EnvironmentObject var workoutManager: WorkoutManager

    private var workoutActive: Bool {
        let s = sessionManager.timerState
        return s.sessionStarted && !s.workoutComplete
    }

    var body: some View {
        NavigationStack {
            if workoutActive {
                WatchTimerView()
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { WatchHomeView() } label: {
                            Image(systemName: "house")
                        }
                    }}
            } else {
                WatchHomeView()
            }
        }
    }
}

private struct WatchHomeView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "figure.run").font(.system(size: 34)).foregroundStyle(.cyan)
            Text("N4x4").font(.system(size: 24, weight: .heavy, design: .rounded))
            Text("Norwegian 4×4").font(.caption).foregroundStyle(.secondary)
            Button { sessionManager.sendStartPause() } label: {
                Label("Start workout", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            if sessionManager.timerState.intervalDuration > 0 {
                Button(role: .destructive) { sessionManager.sendDiscard() } label: {
                    Label("Discard session", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .navigationTitle("N4x4")
    }
}
