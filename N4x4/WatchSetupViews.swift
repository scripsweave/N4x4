// WatchSetupViews.swift
// iOS-side UI for Apple Watch connectivity: an adaptive troubleshooting sheet
// (shown from the timer-screen warning and the Settings status row) and a
// one-time upgrade onboarding sheet for users who added a Watch before the
// app supported one.

import SwiftUI

// MARK: - Troubleshooting

/// Diagnoses why heart rate isn't coming through and walks the user to a fix.
/// Content adapts to the live `watchConnectionStatus` and whether HR is flowing.
struct WatchTroubleshootingView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showMonitorSheet = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: statusIcon)
                            .font(.system(size: 28))
                            .foregroundStyle(statusTint)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(statusTitle).font(.headline)
                            Text(statusDetail)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section(
                    header: Text("Try this"),
                    footer: Text("Heart rate requires an Apple Watch Series 4 or later, or a Bluetooth heart rate monitor. The iPhone has no heart-rate sensor of its own.")
                ) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 24, height: 24)
                                .background(Color.accentColor, in: Circle())
                            Text(step)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 2)
                    }
                }

                // Highest-intent moment for the Bluetooth path: the user is
                // here because heart rate isn't flowing. Hidden once it is.
                if viewModel.currentHeartRate == nil {
                    Section {
                        Button {
                            showMonitorSheet = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "sensor.tag.radiowaves.forward")
                                    .foregroundStyle(.blue)
                                Text("Have a chest strap? Connect it instead")
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Heart Rate Help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showMonitorSheet) {
                HeartRateMonitorSheet(manager: viewModel.bleHeartRateManager)
            }
        }
    }

    // MARK: Adaptive content

    private var statusIcon: String {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired, .appNotInstalled: return "applewatch.slash"
        case .notReachable:                    return "applewatch"
        case .connected:
            return viewModel.currentHeartRate == nil ? "heart.slash" : "applewatch.radiowaves.left.and.right"
        }
    }

    private var statusTint: Color {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired:   return .secondary
        case .appNotInstalled: return .orange
        case .notReachable:    return .orange
        case .connected:       return viewModel.currentHeartRate == nil ? .orange : .green
        }
    }

    private var statusTitle: String {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired:   return "No Apple Watch paired"
        case .appNotInstalled: return "Watch app not installed"
        case .notReachable:    return "Watch app not reachable"
        case .connected:
            return viewModel.currentHeartRate == nil ? "No heart rate yet" : "Connected"
        }
    }

    private var statusDetail: String {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired:
            return "Pair an Apple Watch with this iPhone to stream heart rate."
        case .appNotInstalled:
            return "Install N4x4 on your Watch to stream heart rate."
        case .notReachable:
            return "Open N4x4 on your wrist to connect."
        case .connected:
            return viewModel.currentHeartRate == nil
                ? "Connected, but no heart rate is arriving — usually a Health permission."
                : "\(Int(viewModel.currentHeartRate ?? 0)) BPM streaming."
        }
    }

    private var steps: [String] {
        switch viewModel.watchConnectionStatus {
        case .noWatchPaired:
            return [
                "Open the Apple Watch app on this iPhone.",
                "Follow the prompts to pair your Apple Watch (Series 4 or later).",
                "Once paired, reopen N4x4 and try again.",
            ]
        case .appNotInstalled:
            return [
                "Open the Apple Watch app on this iPhone.",
                "Scroll to ‘Available Apps’ and tap Install next to N4x4 (or enable ‘Automatic App Install’).",
                "On your Watch, open N4x4 and allow Health access when asked.",
                "Start a workout — heart rate should appear within about 10 seconds.",
            ]
        case .notReachable:
            return [
                "Raise your wrist and open N4x4 on the Watch.",
                "Keep the Watch unlocked and close to your iPhone.",
                "Start the workout from either device.",
            ]
        case .connected:
            // Connected but likely a Health-permission problem.
            return [
                "On your Watch, open N4x4 and allow Health access if prompted.",
                "On the Watch: Settings → Privacy & Security → Health → N4x4, and turn on Heart Rate.",
                "On this iPhone: open the Watch app → Privacy → confirm Health access for N4x4.",
                "Keep the Watch snug on your wrist — a loose band blocks the optical sensor.",
                "Stop and restart the workout so the Watch begins a fresh heart-rate session.",
            ]
        }
    }
}

// MARK: - Upgrade onboarding

/// One-time announcement for upgraders: a paired Watch was detected but the
/// Watch app isn't set up yet. Offers a direct route into the setup guide.
struct WatchUpgradeOnboardingView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showGuide = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 64, weight: .regular))
                .foregroundStyle(.red)

            VStack(spacing: 10) {
                Text("New: Apple Watch support")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("Stream live heart rate to N4x4 and get nudged back into your target zone with a tap on the wrist, a spoken cue, or colour — during every interval.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 8)

            VStack(alignment: .leading, spacing: 14) {
                stepRow(number: 1, text: "Install N4x4 on your Apple Watch.")
                stepRow(number: 2, text: "Open it on your wrist and allow Health access.")
                stepRow(number: 3, text: "Start a workout — heart rate appears on both devices.")
            }
            .padding(.horizontal, 4)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    showGuide = true
                } label: {
                    Text("Show me how")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
                Button("Maybe later") { dismiss() }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(28)
        .sheet(isPresented: $showGuide) {
            WatchTroubleshootingView(viewModel: viewModel)
        }
    }

    private func stepRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Color.red, in: Circle())
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}
