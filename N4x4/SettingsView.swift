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

                Section(header: Text("Alarm").font(.headline)) {
                    VStack(alignment: .leading) {
                        Toggle("Alarm at End of Interval", isOn: $viewModel.alarmEnabled)
                            .font(.body)
                        Text("(only works when N4x4 is in the foreground)")
                            .font(.footnote)
                            .foregroundColor(.gray)
                            .padding(.leading, 4) // Optional: add some padding if needed
                    }
                }
                
                Section(header: Text("Display").font(.headline)) {
                                  Toggle("Prevent Phone from Sleeping when Active", isOn: $viewModel.preventSleep)
                                        .font(.body)
                }
                
                Section(header: Text("Notifications").font(.headline)) {
                                    Toggle("Notification at Start of Interval", isOn: $viewModel.notificationsEnabled)
                                        .font(.body)
                }

                // Reset to Defaults Button
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

