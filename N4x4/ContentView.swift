import SwiftUI

final class OnboardingFlowViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case structure
        case notifications
        case reminderDay
        case health
        case launch

        var title: String {
            switch self {
            case .welcome: return "Welcome to N4x4"
            case .structure: return "Train with purpose"
            case .notifications: return "Stay consistent"
            case .reminderDay: return "Pick your workout day"
            case .health: return "Track your progress"
            case .launch: return "You’re ready"
            }
        }
    }

    @Published var currentStep: Step = .welcome

    var progressText: String {
        "\(currentStep.rawValue + 1) of \(Step.allCases.count)"
    }

    func next() {
        guard let nextStep = Step(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextStep
    }

    func back() {
        guard let previousStep = Step(rawValue: currentStep.rawValue - 1) else { return }
        currentStep = previousStep
    }

    func go(to step: Step) {
        currentStep = step
    }

    var isLastStep: Bool { currentStep == .launch }
}

struct ContentView: View {
    @StateObject var viewModel = TimerViewModel()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        TimerView(viewModel: viewModel)
            .fullScreenCover(isPresented: .constant(!hasCompletedOnboarding)) {
                OnboardingView(
                    timerViewModel: viewModel,
                    onComplete: { hasCompletedOnboarding = true },
                    onStartWorkout: {
                        hasCompletedOnboarding = true
                        viewModel.reset()
                        viewModel.startTimer()
                    }
                )
            }
    }
}

private struct OnboardingView: View {
    @ObservedObject var timerViewModel: TimerViewModel
    @StateObject private var flow = OnboardingFlowViewModel()
    @State private var selectedReminderWeekday: Int = TimerViewModel.defaultWorkoutReminderWeekday()
    @State private var isRequestingNotificationPermission = false
    @Environment(\.dismiss) private var dismiss

    let onComplete: () -> Void
    let onStartWorkout: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.7), Color.orange.opacity(0.45)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Text(flow.progressText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))

                    Spacer()

                    if flow.currentStep != .launch {
                        Button("Skip") {
                            onComplete()
                            dismiss()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                    }
                }

                Spacer(minLength: 0)

                Group {
                    switch flow.currentStep {
                    case .welcome:
                        onboardingCard(
                            icon: "figure.run",
                            title: "Hit peak effort in less time.",
                            subtitle: "N4x4 guides each interval so you can focus on effort, not clock-watching."
                        )
                    case .structure:
                        onboardingCard(
                            icon: "timer",
                            title: "Built around proven 4x4 intervals.",
                            subtitle: "Warm up, push hard, recover, repeat. Clean cues keep your workout sharp and simple."
                        )
                    case .notifications:
                        permissionCard(
                            icon: "bell.badge.fill",
                            title: "Get interval cues + comeback reminders",
                            body: "We’ll alert you when each interval changes and can send gentle reminder nudges so momentum never fades.",
                            primaryTitle: "Enable Notifications",
                            secondaryTitle: "Not now",
                            primaryAction: requestNotifications,
                            secondaryAction: flow.next
                        )
                    case .reminderDay:
                        reminderDayCard
                    case .health:
                        permissionCard(
                            icon: "heart.text.square.fill",
                            title: "Unlock Apple Health insights",
                            body: "Log completed workouts and watch your VO₂ max trend improve over time. Great for seeing your cardio fitness gains.",
                            primaryTitle: "Connect Apple Health",
                            secondaryTitle: "Maybe later",
                            primaryAction: requestHealth,
                            secondaryAction: flow.next
                        )
                    case .launch:
                        permissionCard(
                            icon: "bolt.heart.fill",
                            title: "Let’s crush workout #1",
                            body: "Everything’s ready. Start your first guided interval session now.",
                            primaryTitle: "Start First Workout",
                            secondaryTitle: "Finish",
                            primaryAction: {
                                onStartWorkout()
                                dismiss()
                            },
                            secondaryAction: {
                                onComplete()
                                dismiss()
                            }
                        )
                    }
                }

                Spacer(minLength: 0)

                if flow.currentStep == .welcome || flow.currentStep == .structure {
                    HStack(spacing: 12) {
                        if flow.currentStep != .welcome {
                            Button("Back") { flow.back() }
                                .buttonStyle(OnboardingSecondaryButtonStyle())
                        }

                        Button(flow.currentStep == .structure ? "Continue" : "Next") {
                            flow.next()
                        }
                        .buttonStyle(OnboardingPrimaryButtonStyle())
                    }
                }
            }
            .padding(24)
            .onAppear {
                selectedReminderWeekday = timerViewModel.workoutReminderWeekday == 0
                    ? TimerViewModel.defaultWorkoutReminderWeekday()
                    : timerViewModel.workoutReminderWeekday
            }
        }
    }

    private func onboardingCard(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.title3)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.38), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var reminderDayCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text("Which day works best each week?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("Pick your preferred workout day to make consistency easier. You can change this any time in Settings.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))

            Picker("Preferred workout day", selection: $selectedReminderWeekday) {
                ForEach(TimerViewModel.reminderWeekdayOptions, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.wheel)
            .frame(maxHeight: 130)

            VStack(spacing: 12) {
                Button("Save Day") { saveReminderWeekdayAndContinue() }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                Button("Skip for now") { skipReminderWeekdayAndContinue() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.38), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func permissionCard(
        icon: String,
        title: String,
        body: String,
        primaryTitle: String,
        secondaryTitle: String,
        primaryAction: @escaping () -> Void,
        secondaryAction: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 18) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(body)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))

            VStack(spacing: 12) {
                Button(primaryTitle, action: primaryAction)
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial.opacity(0.38), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func requestNotifications() {
        guard !isRequestingNotificationPermission else { return }
        isRequestingNotificationPermission = true

        timerViewModel.refreshNotificationPermissionState {
            defer { isRequestingNotificationPermission = false }

            switch timerViewModel.notificationPermissionState {
            case .granted:
                timerViewModel.notificationsEnabled = true
                timerViewModel.workoutRemindersEnabled = true
                flow.next()
            case .notDetermined, .unknown:
                timerViewModel.notificationsEnabled = true
                timerViewModel.workoutRemindersEnabled = true
                timerViewModel.requestNotificationPermission()
                flow.next()
            case .denied, .unavailable:
                flow.next()
            }
        }
    }

    private func saveReminderWeekdayAndContinue() {
        guard !isRequestingNotificationPermission else { return }
        timerViewModel.workoutReminderMode = .weeklyWeekday
        timerViewModel.workoutReminderWeekday = selectedReminderWeekday
        isRequestingNotificationPermission = true

        timerViewModel.refreshNotificationPermissionState {
            defer { isRequestingNotificationPermission = false }

            switch timerViewModel.notificationPermissionState {
            case .granted:
                timerViewModel.notificationsEnabled = true
                timerViewModel.workoutRemindersEnabled = true
                flow.next()
            case .notDetermined, .unknown:
                timerViewModel.notificationsEnabled = true
                timerViewModel.workoutRemindersEnabled = true
                timerViewModel.requestNotificationPermission()
                flow.next()
            case .denied, .unavailable:
                flow.next()
            }
        }
    }

    private func skipReminderWeekdayAndContinue() {
        flow.next()
    }

    private func requestHealth() {
        if timerViewModel.healthKitPermissionState == .granted {
            timerViewModel.healthKitEnabled = true
            timerViewModel.fetchVO2MaxSamples()
            flow.next()
            return
        }

        timerViewModel.requestHealthKitAuthorizationIfNeeded()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            flow.next()
        }
    }
}

private struct OnboardingPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.86 : 1.0), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
    }
}

private struct OnboardingSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white.opacity(configuration.isPressed ? 0.12 : 0.16), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            }
    }
}
