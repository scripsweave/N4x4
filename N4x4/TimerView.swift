// TimerView.swift

import SwiftUI

struct TimerView: View {
    @ObservedObject var viewModel: TimerViewModel
    @State private var showSettings = false
    @State private var showResetAlert = false
    @Environment(\.scenePhase) private var scenePhase

    // Computed property for ring color
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

    // Computed property for interval name with count
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

                VStack(spacing: 40) {
                    // Interval Name
                    Text(currentIntervalName)
                        .font(.system(size: 34, weight: .semibold, design: .default))
                        .foregroundColor(.primary)

                    // Timer Circle and Text
                    ZStack {
                        // Background Circle
                        Circle()
                            .stroke(lineWidth: 15)
                            .foregroundColor(Color(UIColor.systemGray5))

                        // Animated Ring
                        Circle()
                            .trim(from: 0, to: CGFloat(viewModel.timeRemaining) / CGFloat(viewModel.intervals[viewModel.currentIntervalIndex].duration))
                            .stroke(style: StrokeStyle(lineWidth: 15, lineCap: .round))
                            .foregroundColor(ringColor)
                            .rotationEffect(Angle(degrees: -90))
                            .animation(.linear(duration: 1), value: viewModel.timeRemaining)

                        // Timer Text
                        Text(timeString(time: viewModel.timeRemaining))
                            .font(.system(size: 50, weight: .bold, design: .default))
                            .foregroundColor(.primary)
                    }
                    .frame(width: 250, height: 250)

                    // Control Buttons
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
                }
                .padding()

                // Display "Workout Complete!" when the workout is finished
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
                        // Hide the message after 5 seconds and reset the app
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
                    // Update timeRemaining when app becomes active
                    if viewModel.isRunning {
                        viewModel.timeRemaining = viewModel.intervalEndTime?.timeIntervalSinceNow ?? viewModel.timeRemaining
                    }
                }
            }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
            }
        }
    }

    // Helper function
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
