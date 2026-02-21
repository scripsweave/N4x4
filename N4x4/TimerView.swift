// TimerView.swift

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct TimerView: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showResetAlert = false
    @Environment(\.scenePhase) private var scenePhase

    var ringColor: Color {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else {
            return .gray
        }

        switch viewModel.intervals[viewModel.currentIntervalIndex].type {
        case .warmup:
            return .blue
        case .highIntensity:
            return .red
        case .rest:
            return .green
        }
    }

    var currentIntervalName: String {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else {
            return "Ready"
        }

        let interval = viewModel.intervals[viewModel.currentIntervalIndex]
        let totalIntervals = viewModel.numberOfIntervals

        switch interval.type {
        case .warmup:
            return interval.name
        case .highIntensity:
            return "\(interval.name) (\(viewModel.highIntensityCount)/\(totalIntervals))"
        case .rest:
            return "\(interval.name) (\(viewModel.restCount)/\(totalIntervals))"
        }
    }

    var progressValue: CGFloat {
        guard viewModel.intervals.indices.contains(viewModel.currentIntervalIndex) else { return 0 }
        let duration = max(1, viewModel.intervals[viewModel.currentIntervalIndex].duration)
        let raw = viewModel.timeRemaining / duration
        return CGFloat(min(1, max(0, raw)))
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color(UIColor.systemBackground)
                    .edgesIgnoringSafeArea(.all)

                VStack(spacing: 24) {
                    Text(currentIntervalName)
                        .font(.system(size: 34, weight: .semibold, design: .default))
                        .foregroundColor(.primary)

                    ZStack {
                        Circle()
                            .stroke(lineWidth: 15)
                            .foregroundColor(Color(UIColor.systemGray5))

                        Circle()
                            .trim(from: 0, to: progressValue)
                            .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .round))
                            .foregroundColor(ringColor)
                            .rotationEffect(Angle(degrees: -90))
                            .animation(.linear(duration: 1), value: viewModel.timeRemaining)

                        Text(timeString(time: viewModel.timeRemaining))
                            .font(.system(size: 50, weight: .bold, design: .default))
                            .foregroundColor(.primary)
                    }
                    .frame(width: 250, height: 250)

                    HStack(spacing: 50) {
                        Button(action: {
                            viewModel.pause()
                        }) {
                            Image(systemName: viewModel.isRunning ? "pause.circle" : "play.circle")
                                .font(.system(size: 50, weight: .regular, design: .default))
                                .foregroundColor(.primary)
                        }

                        Button(action: {
                            viewModel.skip()
                        }) {
                            Image(systemName: "forward.end.alt")
                                .font(.system(size: 50, weight: .regular, design: .default))
                                .foregroundColor(.primary)
                        }
                    }

                    vo2Section
                }
                .padding()
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    showResetAlert = true
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                },
                trailing: HStack(spacing: 16) {
                    Button(action: {
                        showHistory = true
                    }) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.title3)
                    }

                    Button(action: {
                        showSettings = true
                    }) {
                        Image(systemName: "gear")
                            .font(.title2)
                    }
                }
            )
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
            }
            .sheet(isPresented: $showHistory) {
                WorkoutHistoryView(viewModel: viewModel)
            }
            .sheet(isPresented: $viewModel.showPostWorkoutSummary) {
                PostWorkoutSummaryView(viewModel: viewModel)
            }
            .alert(isPresented: $showResetAlert) {
                Alert(
                    title: Text("Reset Session"),
                    message: Text("Are you sure you want to reset the session?"),
                    primaryButton: .destructive(Text("Reset")) {
                        viewModel.reset()
                    },
                    secondaryButton: .cancel()
                )
            }
            .onChange(of: viewModel.isRunning) { _, _ in
                updateIdleTimer()
            }
            .onChange(of: viewModel.preventSleep) { _, _ in
                updateIdleTimer()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    viewModel.refreshNotificationPermissionState()
                    viewModel.refreshHealthKitAuthorizationState()
                    if viewModel.isRunning {
                        viewModel.reconcileTimerState(now: Date(), playAlarm: false)
                    }
                    if viewModel.healthKitEnabled {
                        viewModel.fetchVO2MaxSamples()
                    }
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    @ViewBuilder
    var vo2Section: some View {
        if viewModel.healthKitEnabled && viewModel.vo2DataPoints.count >= 2 {
#if canImport(Charts)
            VStack(alignment: .leading, spacing: 8) {
                Text("VO₂ Max Trend")
                    .font(.headline)
                Chart(viewModel.vo2DataPoints) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("VO₂", point.value)
                    )
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("VO₂", point.value)
                    )
                }
                .frame(height: 160)
            }
#else
            Text("VO₂ max data available. Trend chart requires iOS Charts support.")
                .font(.footnote)
                .foregroundColor(.secondary)
#endif
        }
    }



private struct PostWorkoutSummaryView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Workout complete")) {
                    Picker("Type", selection: $viewModel.selectedWorkoutType) {
                        ForEach(WorkoutType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    TextField("Notes (optional)", text: $viewModel.workoutNotesDraft, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section {
                    Button("Save to Log") {
                        viewModel.saveWorkoutLogEntryAndResetSession()
                        dismiss()
                    }
                    .font(.headline)
                }
            }
            .navigationTitle("Session Saved?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        viewModel.closePostWorkoutSummaryWithoutSaving()
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct WorkoutHistoryView: View {
    @ObservedObject var viewModel: TimerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            List {
                if viewModel.workoutLogEntries.isEmpty {
                    Text("No workouts logged yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.workoutLogEntries) { entry in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.workoutType.rawValue)
                                .font(.headline)
                            Text(entry.completedAt, style: .date)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            if !entry.notes.isEmpty {
                                Text(entry.notes)
                                    .font(.subheadline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Workout Log")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

    func timeString(time: TimeInterval) -> String {
        let minutes = Int(time) / 60 % 60
        let seconds = Int(time) % 60
        return String(format: "%02i:%02i", minutes, seconds)
    }

    func updateIdleTimer() {
        if viewModel.isRunning && viewModel.preventSleep {
            UIApplication.shared.isIdleTimerDisabled = true
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
