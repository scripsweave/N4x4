// WatchHomeView.swift
// Idle Home and post-workout Complete screens. Home mirrors the phone's Home:
// streak header, the brand-glow START ring, and the interval plan underneath.
// START always works — with the phone in reach the phone leads, otherwise the
// Watch runs the last synced plan itself and hands the phone the result later.
// Complete is mode-aware: a phone-led session is saved on the phone; a
// Watch-led one shows its summary and sync status here.

import SwiftUI

// MARK: - Home

struct WatchHomeView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager

    private var state: WatchTimerState { sessionManager.timerState }
    private var hasPlan: Bool { state.hasPlan }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width * 0.70, geo.size.height * 0.60)
            VStack(spacing: 0) {
                header
                Spacer(minLength: 2)

                Button { sessionManager.startWorkout() } label: {
                    NeonRing(side: side,
                             progress: 1,
                             glow: AnyShapeStyle(WatchPalette.brandGlow),
                             glowColor: WatchPalette.amber) {
                        Text("START")
                            .font(.system(size: side * 0.19, weight: .heavy, design: .rounded))
                            .foregroundStyle(WatchPalette.textPrimary)
                    }
                }
                .buttonStyle(.plain)

                Spacer(minLength: 2)
                footer
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.horizontal, 8)
    }

    /// Week streak, exactly as the phone's Home header. Falls back to the app
    /// name until the first state sync (no streak to show yet).
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if sessionManager.hasReceivedState {
                Image(systemName: state.streak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(state.streak > 0 ? WatchPalette.amber : WatchPalette.textTertiary)
                Text("\(state.streak)")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                Text("WEEK STREAK")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WatchPalette.textSecondary)
                    .tracking(0.5)
            } else {
                Text("N4x4")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
            }
            Spacer(minLength: 0)
            if !sessionManager.pendingWorkouts.isEmpty {
                // A finished Watch workout still waiting for the phone.
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(WatchPalette.textTertiary)
            }
        }
        .foregroundStyle(WatchPalette.textPrimary)
        .lineLimit(1)
    }

    /// Plan preview (timeline + "4 intervals · ~28 min") and where the
    /// workout will run.
    private var footer: some View {
        VStack(spacing: 4) {
            if hasPlan {
                WatchTimelineBar(phases: state.planPhases, durations: state.planDurations)
                Text(planSummary)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WatchPalette.textTertiary)
            } else {
                Text(sessionManager.isReachable ? "Norwegian 4×4" : "Norwegian 4×4 · default plan")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WatchPalette.textSecondary)
            }
            if !sessionManager.isReachable {
                HStack(spacing: 3) {
                    Image(systemName: "applewatch")
                    Text("No iPhone · runs on Watch")
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(WatchPalette.electricBlue)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    private var planSummary: String {
        let mins = Int((state.planTotal / 60).rounded())
        return "\(state.totalIntervals) intervals · ~\(mins) min"
    }
}

// MARK: - Complete

struct WatchCompleteView: View {
    @EnvironmentObject var sessionManager: WatchSessionManager
    @State private var showDiscardAlert = false

    private var isLocal: Bool { sessionManager.mode == .local }
    private var record: CompletedWatchWorkout? { sessionManager.engine?.completedRecord() }
    private var isPending: Bool {
        guard let id = record?.id else { return false }
        return sessionManager.pendingWorkouts.contains { $0.id == id }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(WatchPalette.recovery)
                    .shadow(color: WatchPalette.recovery.opacity(0.6), radius: 8)

                Text("WORKOUT COMPLETE")
                    .font(.system(size: 13, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(WatchPalette.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if isLocal {
                    localSummary
                    Button { sessionManager.dismissCompletedLocalWorkout() } label: {
                        Text("DONE")
                    }
                    .buttonStyle(WatchControlButtonStyle())
                    .padding(.top, 2)
                } else {
                    Text("Review your workout on your iPhone.")
                        .font(.system(size: 11))
                        .foregroundStyle(WatchPalette.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { showDiscardAlert = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash").font(.system(size: 12, weight: .bold))
                        Text("DELETE")
                    }
                }
                .buttonStyle(WatchControlButtonStyle(tint: WatchPalette.danger, outlined: true))
                .disabled(!isLocal && !sessionManager.isReachable)
                .opacity(!isLocal && !sessionManager.isReachable ? 0.45 : 1)
                .padding(.top, isLocal ? 0 : 2)
            }
            .padding(.horizontal, 8)
        }
        .alert("Delete workout?", isPresented: $showDiscardAlert) {
            Button("Delete", role: .destructive) {
                if isLocal { sessionManager.discardCompletedLocalWorkout() }
                else { sessionManager.discardPhoneWorkout() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the workout from N4x4 history.")
        }
    }

    /// Duration · average HR, then whether the phone has it yet.
    @ViewBuilder private var localSummary: some View {
        if let record {
            Text(summaryLine(record))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(WatchPalette.textSecondary)
                .monospacedDigit()
            HStack(spacing: 4) {
                Image(systemName: isPending ? "iphone.slash" : "iphone.badge.checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text(isPending ? "Will sync to iPhone" : "Saved on iPhone")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(isPending ? WatchPalette.textTertiary : WatchPalette.recovery)
        }
    }

    private func summaryLine(_ r: CompletedWatchWorkout) -> String {
        let mins = Int((r.totalSeconds / 60).rounded())
        if let avg = r.averageBPM { return "\(mins) min · avg \(avg) bpm" }
        return "\(mins) min"
    }
}
