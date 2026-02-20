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
                Section(header: Text("Intervals").font(.headline)) {
                    Stepper(value: $viewModel.numberOfIntervals, in: 1...10) {
                        Text("Number of Intervals: \(viewModel.numberOfIntervals)")
                            .font(.body)
                    }
                }

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
                        Text("Rest Duration: \(Int(viewModel.restDuration / 60)) min")
                            .font(.body)
                    }
                }

                Section(header: Text("Heart Rate Guide").font(.headline)) {
                    HeartRateGuidanceCard(viewModel: viewModel)
                        .listRowInsets(EdgeInsets())
                }

                Section(header: Text("Alarm").font(.headline)) {
                    VStack(alignment: .leading) {
                        Toggle("Alarm at End of Interval", isOn: $viewModel.alarmEnabled)
                            .font(.body)
                        Text("(only works when N4x4 is in the foreground)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.leading, 4)
                    }
                }

                Section(header: Text("Display").font(.headline)) {
                    Toggle("Prevent Phone from Sleeping when Active", isOn: $viewModel.preventSleep)
                        .font(.body)
                }

                Section(header: Text("Interval Notifications").font(.headline)) {
                    Toggle("Notification at Start of Interval", isOn: $viewModel.notificationsEnabled)
                        .font(.body)

                    if viewModel.notificationPermissionState == .denied {
                        permissionDeniedView(
                            "Notifications are denied for N4x4. Enable them in Settings to receive interval and reminder alerts."
                        )
                    }
                }

                Section(header: Text("Workout Reminders").font(.headline)) {
                    Toggle("Reminder Notifications", isOn: $viewModel.workoutRemindersEnabled)

                    Picker("Reminder Schedule", selection: Binding(
                        get: { viewModel.workoutReminderMode },
                        set: { viewModel.workoutReminderMode = $0 }
                    )) {
                        ForEach(WorkoutReminderMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }

                    if viewModel.workoutReminderMode == .everyXDays {
                        Stepper(value: $viewModel.workoutReminderDays, in: 1...30) {
                            Text("Every \(viewModel.workoutReminderDays) day(s)")
                        }
                    } else {
                        Picker("Reminder Day", selection: $viewModel.workoutReminderWeekday) {
                            ForEach(TimerViewModel.reminderWeekdayOptions, id: \.value) { option in
                                Text(option.title).tag(option.value)
                            }
                        }
                    }

                    Text("Pick the style that feels easiest to keep.")
                        .font(.footnote)
                        .foregroundColor(.gray)

                    if viewModel.notificationPermissionState == .denied {
                        permissionDeniedView(
                            "Reminder notifications are denied for N4x4. You can still choose a schedule and enable alerts later in Settings."
                        )
                    }
                }

                Section(header: Text("Apple Health").font(.headline)) {
                    Toggle("Enable Apple Health", isOn: $viewModel.healthKitEnabled)
                        .onChange(of: viewModel.healthKitEnabled) { _, enabled in
                            if enabled {
                                viewModel.requestHealthKitAuthorizationIfNeeded()
                            }
                        }

                    if viewModel.healthKitPermissionState == .denied {
                        permissionDeniedView(
                            "Apple Health access is denied. Enable workout and VO₂ permissions in Settings to sync completed sessions."
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

                Section(header: Text("Onboarding").font(.headline)) {
                    Text("You can replay the first-run guide any time.")
                        .font(.footnote)
                        .foregroundColor(.secondary)

                    Button("Replay Onboarding") {
                        hasCompletedOnboarding = false
                        presentationMode.wrappedValue.dismiss()
                    }
                }

                Section {
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

    @ViewBuilder
    private func permissionDeniedView(_ message: String) -> some View {
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
