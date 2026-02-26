// SettingsView

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.presentationMode) var presentationMode
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showResetAlert = false

    var body: some View {
        NavigationView {
            Form {
                // Intervals
                Section(header: Text("Intervals").font(.headline)) {
                    Stepper(value: $viewModel.numberOfIntervals, in: 1...10) {
                        Text("Number of Intervals: \(viewModel.numberOfIntervals)")
                            .font(.body)
                    }
                }

                // Durations (part of Intervals)
                Section(header: Text("Durations (Minutes)").font(.headline)) {
                    Stepper(value: $viewModel.warmupDuration, in: 0...600, step: 60) {
                        Text("Warmup Duration: \(Int(viewModel.warmupDuration / 60)) min")
                            .font(.body)
                    }

                    Stepper(value: $viewModel.highIntensityDuration, in: 60...600, step: 60) {
                        Text("High Intensity Duration: \(Int(viewModel.highIntensityDuration / 60)) min")
                            .font(.body)
                    }

                    Stepper(value: $viewModel.restDuration, in: 60...600, step: 60) {
                        Text("Recovery Duration: \(Int(viewModel.restDuration / 60)) min")
                            .font(.body)
                    }
                }

                // Audio Alerts
                Section(header: Text("Audio Alerts").font(.headline)) {
                    Picker("Audio Alerts", selection: $viewModel.audioMode) {
                        ForEach(AudioMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Group {
                        switch viewModel.audioMode {
                        case .alarm:
                            Text("A beep plays at each interval change (foreground only).")
                        case .voice:
                            Text("Voice cues at start, halfway, and 30 seconds to go. Music softens while speaking.")
                        case .silent:
                            Text("No audio alerts. Watch the screen for interval changes.")
                        }
                    }
                    .font(.footnote)
                    .foregroundColor(.secondary)
                }

                // Display
                Section(header: Text("Display").font(.headline)) {
                    Toggle("Prevent Phone from Sleeping when Active", isOn: $viewModel.preventSleep)
                        .font(.body)
                    Toggle("Haptic Feedback at Interval Changes", isOn: $viewModel.hapticsEnabled)
                        .font(.body)
                    Toggle("Live Activity / Dynamic Island", isOn: $viewModel.liveActivitiesEnabled)
                        .font(.body)
                    Text("Shows interval countdown on the Lock Screen and Dynamic Island during a workout.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }

                // Interval Notifications
                Section(header: Text("Interval Notifications").font(.headline)) {
                    Toggle("Notification at Start of Interval", isOn: $viewModel.notificationsEnabled)
                        .font(.body)

                    if viewModel.notificationPermissionState == .denied {
                        permissionDeniedView(
                            "Notifications are denied for N4x4. Enable them in Settings to receive interval and reminder alerts.",
                            viewModel: viewModel
                        )
                    }
                }

                // Reminder Notifications
                Section(header: Text("Reminder Notifications").font(.headline)) {
                    Toggle("Reminder Notifications", isOn: $viewModel.workoutRemindersEnabled)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select workout days")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(TimerViewModel.reminderWeekdayOptions, id: \.value) { option in
                                Button(action: {
                                    viewModel.toggleWeekday(option.value)
                                }) {
                                    Text(String(option.title.prefix(3)))
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(viewModel.isWeekdaySelected(option.value) ? .white : .primary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(viewModel.isWeekdaySelected(option.value) ? Color.accentColor : Color.gray.opacity(0.2))
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                            
                            if !viewModel.selectedWeekdays.isEmpty {
                                Text("\(viewModel.selectedWeekdays.count) day\(viewModel.selectedWeekdays.count == 1 ? "" : "s") selected per week")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    if hasConsecutiveDays(viewModel.selectedWeekdays) {
                        Label(
                            "Consecutive days aren't recommended — allow 48–72 hours of recovery between sessions.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundColor(.orange)
                    }

                    Text("Pick the style that feels easiest to keep.")
                        .font(.footnote)
                        .foregroundColor(.gray)

                    if viewModel.notificationPermissionState == .denied {
                        permissionDeniedView(
                            "Reminder notifications are denied for N4x4. You can still choose a schedule and enable alerts later in Settings.",
                            viewModel: viewModel
                        )
                    }
                }

                // Heart Rate Guide
                Section(header: Text("Heart Rate Guide").font(.headline)) {
                    HeartRateGuidanceCard(viewModel: viewModel, showInstructions: false)
                        .listRowInsets(EdgeInsets())
                }

                // VO₂ max goal
                Section(header: Text("VO₂ Max Goal").font(.headline)) {
                    Picker("Biological Sex", selection: $viewModel.userBiologicalSexRaw) {
                        ForEach(BiologicalSex.allCases, id: \.rawValue) { sex in
                            Text(sex.rawValue).tag(sex.rawValue)
                        }
                    }

                    Picker("Goal", selection: $viewModel.vo2TargetTierRaw) {
                        Text("None").tag("")
                        ForEach(VO2TargetTier.allCases, id: \.rawValue) { tier in
                            let value = TimerViewModel.vo2TargetValue(
                                age: viewModel.userAge,
                                sex: viewModel.userBiologicalSex,
                                tier: tier
                            )
                            Text("\(tier.rawValue) — \(Int(value)) mL/kg/min").tag(tier.rawValue)
                        }
                    }

                    if let target = viewModel.vo2MaxTarget, let tier = viewModel.vo2TargetTier {
                        Text("Target: \(Int(target)) mL/kg/min (\(tier.description))")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }

                // Apple Health
                Section(header: Text("Apple Health").font(.headline)) {
                    Toggle("Enable Apple Health", isOn: $viewModel.healthKitEnabled)
                        .onChange(of: viewModel.healthKitEnabled) { _, enabled in
                            if enabled {
                                viewModel.requestHealthKitAuthorizationIfNeeded()
                            }
                        }

                    if viewModel.healthKitEnabled {
                        Toggle("Log Workouts to Apple Health", isOn: $viewModel.logWorkoutsToHealthKit)
                    }

                    if viewModel.healthKitPermissionState == .denied {
                        permissionDeniedView(
                            "Apple Health access is denied. Enable workout and VO₂ permissions in Settings to sync completed sessions.",
                            viewModel: viewModel
                        )
                    }

                    Button("Refresh VO₂ max Data") {
                        viewModel.fetchVO2MaxSamples()
                    }
                    .disabled(!viewModel.healthKitEnabled)

                    Text(viewModel.healthAuthorizationGranted ? "Connected" : "Not connected")
                        .font(.footnote)
                        .foregroundColor(viewModel.healthAuthorizationGranted ? .green : .secondary)
                }

                // Onboarding
                Section(header: Text("Onboarding").font(.headline)) {
                    Text("You can replay the first-run guide any time.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button("Replay Onboarding") {
                        hasCompletedOnboarding = false
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                // Reset
                Section(header: Text("Reset").font(.headline)) {
                    Button(action: {
                        showResetAlert = true
                    }) {
                        Text("Reset to Defaults")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarItems(trailing: Button("Done") {
                presentationMode.wrappedValue.dismiss()
            })
            .alert(isPresented: $showResetAlert) {
                Alert(
                    title: Text("Reset to Defaults"),
                    message: Text("Are you sure you want to reset all settings to their default values?"),
                    primaryButton: .destructive(Text("Reset")) {
                        viewModel.resetSettingsToDefaults()
                    },
                    secondaryButton: .cancel()
                )
            }
            .onAppear {
                viewModel.refreshNotificationPermissionState()
                viewModel.refreshHealthKitAuthorizationState()
            }
        }
    }

    private func hasConsecutiveDays(_ days: [Int]) -> Bool {
        guard days.count >= 2 else { return false }
        let sorted = days.sorted()
        for i in 0..<(sorted.count - 1) {
            if sorted[i + 1] - sorted[i] == 1 { return true }
        }
        return sorted.contains(7) && sorted.contains(1)
    }

    @ViewBuilder
    private func permissionDeniedView(_ message: String, viewModel: TimerViewModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.footnote)
                .foregroundColor(.secondary)

            Button("Open Settings") {
                viewModel.openAppSettings()
            }
            .font(.footnote)
        }
        .padding(.vertical, 4)
    }
}
