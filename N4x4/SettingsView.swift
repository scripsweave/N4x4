// SettingsView

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.presentationMode) var presentationMode
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
                }

                Section(header: Text("Workout Reminders").font(.headline)) {
                    Toggle("Reminder Notifications", isOn: $viewModel.workoutRemindersEnabled)
                    Stepper(value: $viewModel.workoutReminderDays, in: 1...30) {
                        Text("Every \(viewModel.workoutReminderDays) day(s)")
                    }
                    Text("Default is weekly (7 days).")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }

                Section(header: Text("Apple Health").font(.headline)) {
                    Toggle("Enable Apple Health", isOn: $viewModel.healthKitEnabled)
                        .onChange(of: viewModel.healthKitEnabled) { enabled in
                            if enabled {
                                viewModel.requestHealthKitAuthorizationIfNeeded()
                            }
                        }

                    Button("Refresh VO₂ max Data") {
                        viewModel.fetchVO2MaxSamples()
                    }
                    .disabled(!viewModel.healthKitEnabled)

                    Text(viewModel.healthAuthorizationGranted ? "Connected" : "Not connected")
                        .font(.footnote)
                        .foregroundColor(viewModel.healthAuthorizationGranted ? .green : .secondary)
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
        }
    }
}
