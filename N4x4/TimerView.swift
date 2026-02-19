// TimerView.swift

import SwiftUI
#if canImport(Charts)
import Charts
#endif

struct TimerView: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var showSettings = false
    @State private var showResetAlert = false
    @Environment(\.scenePhase) private var scenePhase

    var ringColor: Color {
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
                            .trim(from: 0, to: CGFloat(viewModel.timeRemaining) / CGFloat(viewModel.intervals[viewModel.currentIntervalIndex].duration))
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

                    HeartRateGuidanceCard(viewModel: viewModel, showInstructions: false)

                    vo2Section
                }
                .padding()

                if viewModel.showCompletionMessage {
                    ZStack {
                        Color.black.opacity(0.8)
                            .edgesIgnoringSafeArea(.all)
                        Text("Workout Complete!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            withAnimation {
                                viewModel.showCompletionMessage = false
                                viewModel.reset()
                            }
                        }
                    }
                }
            }
            .navigationBarTitle("", displayMode: .inline)
            .navigationBarItems(
                leading: Button(action: {
                    showResetAlert = true
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.title2)
                },
                trailing: Button(action: {
                    showSettings = true
                }) {
                    Image(systemName: "gear")
                        .font(.title2)
                }
            )
            .sheet(isPresented: $showSettings) {
                SettingsView(viewModel: viewModel)
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
            .onChange(of: viewModel.isRunning) { _ in
                updateIdleTimer()
            }
            .onChange(of: viewModel.preventSleep) { _ in
                updateIdleTimer()
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    if viewModel.isRunning {
                        viewModel.timeRemaining = viewModel.intervalEndTime?.timeIntervalSinceNow ?? viewModel.timeRemaining
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
        if viewModel.healthKitEnabled {
            if viewModel.vo2DataPoints.count >= 2 {
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
            } else {
                Text("No VO₂ max trend yet. Apple Health data will appear here when available.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
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
