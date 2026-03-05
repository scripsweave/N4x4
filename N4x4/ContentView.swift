import SwiftUI

final class OnboardingFlowViewModel: ObservableObject {
    enum Step: Int, CaseIterable {
        case welcome
        case basics
        case modality
        case age
        case vo2Goal
        case reminderDay
        case audioMode
        case notifications
        case health
        case launch

        var title: String {
            switch self {
            case .welcome: return "Welcome to N4x4"
            case .basics: return "How it works"
            case .modality: return "Choose your exercise"
            case .age: return "Set your heart rate zones"
            case .vo2Goal: return "Set your VO₂ max goal"
            case .reminderDay: return "Pick your training days"
            case .audioMode: return "How should we guide you?"
            case .notifications: return "Stay consistent"
            case .health: return "Track your progress"
            case .launch: return "You're ready"
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
                    if flow.currentStep != .welcome && !flow.isLastStep {
                        Button(action: { flow.back() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("Back")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white.opacity(0.8))
                        }
                    } else {
                        Color.clear.frame(width: 50, height: 20)
                    }

                    Spacer()

                    Text(flow.progressText)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.8))
                }

                Spacer(minLength: 0)

                Group {
                    switch flow.currentStep {
                    case .welcome:
                        welcomeCard
                    case .basics:
                        basicsCard
                    case .modality:
                        modalityCard
                    case .age:
                        ageCard
                    case .audioMode:
                        audioModeCard
                    case .notifications:
                        permissionCard(
                            icon: "bell.badge.fill",
                            title: "Get interval cues + comeback reminders",
                            body: "We'll alert you when each interval changes and can send gentle reminder nudges so momentum never fades.",
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
                            title: "Connect to Apple Health",
                            body: "Automatically save your N4x4 workouts to Apple Health and track your VO₂ max over time. Great for seeing your cardio fitness gains.",
                            primaryTitle: "Connect & Log Workouts",
                            secondaryTitle: "Maybe later",
                            primaryAction: requestHealth,
                            secondaryAction: flow.next
                        )
                    case .vo2Goal:
                        vo2GoalCard
                    case .launch:
                        permissionCard(
                            icon: "bolt.heart.fill",
                            title: "Let's crush workout #1",
                            body: "Everything's ready. Start your first guided interval session now.",
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

            }
            .padding(24)
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
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var ageCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "heart.text.square.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text("Let's personalize your training")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Text("We use your age to calculate your target heart rate zones. This helps you train at the right intensity for maximum VO₂ max improvement.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 8)

            Picker("Max HR method", selection: $timerViewModel.useCustomMaxHR) {
                Text("Based on age").tag(false)
                Text("Custom Heart Rate").tag(true)
            }
            .pickerStyle(.segmented)
            .colorMultiply(.white)
            .onChange(of: timerViewModel.useCustomMaxHR) { _, isCustom in
                if isCustom && timerViewModel.customMaxHR == 0 {
                    timerViewModel.customMaxHR = timerViewModel.maximumHeartRate
                }
            }

            VStack(spacing: 12) {
                if timerViewModel.useCustomMaxHR {
                    Picker("Max HR", selection: $timerViewModel.customMaxHR) {
                        ForEach(100...220, id: \.self) { bpm in
                            Text("\(bpm)").tag(bpm)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .clipped()
                    .colorScheme(.dark)
                } else {
                    Picker("Age", selection: $timerViewModel.userAge) {
                        ForEach(TimerViewModel.minimumSupportedAge...TimerViewModel.maximumSupportedAge, id: \.self) { age in
                            Text("\(age)").tag(age)
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 120)
                    .clipped()
                    .colorScheme(.dark)
                    Text(timerViewModel.userAge >= 40
                         ? "Using Tanaka formula (208 − 0.7 × age)"
                         : "Using 220 − age")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }

                Text("Your max heart rate: \(timerViewModel.maximumHeartRate) BPM")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.top, 8)
            .onAppear {
                if timerViewModel.useCustomMaxHR && timerViewModel.customMaxHR == 0 {
                    timerViewModel.customMaxHR = timerViewModel.maximumHeartRate
                }
            }

            VStack(spacing: 12) {
                Button("Continue") {
                    flow.next()
                }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private var audioModeCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text("How should we guide you?")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("You can change this any time in Settings.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 10) {
                audioModeRow(
                    mode: .voice,
                    icon: "waveform",
                    description: "Hear what's coming and get hyped up. Music softens while we speak."
                )
                audioModeRow(
                    mode: .alarm,
                    icon: "bell.fill",
                    description: "A sharp beep at every interval change."
                )
                audioModeRow(
                    mode: .silent,
                    icon: "speaker.slash.fill",
                    description: "No audio alerts — keep an eye on the screen."
                )
            }

            Button("Confirm Selection") {
                flow.next()
            }
            .buttonStyle(OnboardingPrimaryButtonStyle())
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func audioModeRow(mode: AudioMode, icon: String, description: String) -> some View {
        Button {
            timerViewModel.audioMode = mode
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 28)
                    .foregroundStyle(.white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.rawValue)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                Image(systemName: timerViewModel.audioMode == mode
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(timerViewModel.audioMode == mode
                          ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
            )
        }
    }

    private var reminderDayCard: some View {
        let selectedCount = timerViewModel.selectedWeekdays.count
        let hasConsecutive = hasConsecutiveDays(timerViewModel.selectedWeekdays)

        return VStack(spacing: 18) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text("Pick your training days")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Recommendation based on goal tier
            Group {
                switch timerViewModel.vo2TargetTier {
                case .good:
                    Text("For your Good goal, 1 session per week is ideal. Consistency matters more than frequency.")
                case .amazing:
                    Text("For your Amazing goal, aim for 2 sessions per week to keep the adaptations coming.")
                case .elite:
                    Text("For your Elite goal, 3 sessions per week will drive serious VO₂ max gains.")
                case nil:
                    Text("Health experts recommend at least 1 Norwegian 4x4 per week. You can always adjust later.")
                }
            }
            .font(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 8)

            // Day grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(TimerViewModel.reminderWeekdayOptions, id: \.value) { option in
                    Button(action: {
                        timerViewModel.toggleWeekday(option.value)
                    }) {
                        Text(String(option.title.prefix(3)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(timerViewModel.isWeekdaySelected(option.value) ? .black : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(timerViewModel.isWeekdaySelected(option.value) ? Color.white : Color.white.opacity(0.2))
                            )
                    }
                }
            }
            .padding(.horizontal, 8)

            if selectedCount > 0 {
                Text("\(selectedCount) day\(selectedCount == 1 ? "" : "s") selected per week")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }

            // Consecutive day warning
            if hasConsecutive {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.footnote)
                    Text("Consecutive days aren't recommended — your muscles need 48–72 hours to recover and adapt between sessions.")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(12)
                .background(Color.yellow.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 4)
            }

            VStack(spacing: 12) {
                Button(selectedCount > 0 ? "Save My Training Days" : "Skip for now") {
                    saveReminderWeekdayAndContinue()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())
                Button("I'll decide later") { skipReminderWeekdayAndContinue() }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    /// Returns true if any two selected weekdays are adjacent in the calendar week.
    private func hasConsecutiveDays(_ days: [Int]) -> Bool {
        guard days.count >= 2 else { return false }
        let sorted = days.sorted()
        for i in 0..<(sorted.count - 1) {
            if sorted[i + 1] - sorted[i] == 1 { return true }
        }
        // Wrap-around: Saturday (7) and Sunday (1)
        return sorted.contains(7) && sorted.contains(1)
    }

    // MARK: - Welcome card

    private var welcomeCard: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(.white)
                .padding(18)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text("N4x4 — the ultimate way to improve your VO₂ max")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text("N4x4 helps you train consistently to reach your VO₂ max goals through High Intensity Interval Training.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            VStack(spacing: 12) {
                Button(action: { flow.next() }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.magnifyingglass")
                        Text("Show me how it works")
                    }
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                Button(action: { flow.go(to: .age) }) {
                    Text("Skip intro, get started →")
                }
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    // MARK: - Protocol basics card

    private var basicsCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text("How N4x4 Works")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            // Protocol steps
            VStack(spacing: 10) {
                basicsStep(icon: "figure.walk",        color: Color(red: 0.35, green: 0.60, blue: 1.0),
                           label: "Warm-up",    detail: "5 minutes at an easy, increasing pace")
                basicsStep(icon: "bolt.fill",           color: .orange,
                           label: "Work Hard",  detail: "4 minutes · 85–95% max heart rate")
                basicsStep(icon: "heart.fill",          color: Color(red: 0.15, green: 0.80, blue: 0.50),
                           label: "Active Rest", detail: "3 minutes · 60–70% max heart rate")
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.75))
                    Text("Repeat Work + Rest × 4 times")
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                }
                basicsStep(icon: "figure.walk.motion", color: .cyan,
                           label: "Cool-down",  detail: "5 minutes of light movement")
            }
            .padding(14)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))

            // Key notes
            VStack(alignment: .leading, spacing: 6) {
                basicsNote("Can't speak in full sentences? You're at the right intensity.")
                basicsNote("Start with 2 intervals and build up to 4 over several weeks.")
                basicsNote("Allow 48–72 hours of recovery between sessions.")
                basicsNote("⚠️ Consult a healthcare professional if you have any health conditions.",
                           muted: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))

            VStack(spacing: 12) {
                Button("Choose Your Exercise →") { flow.next() }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                Button("Skip") { flow.go(to: .age) }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func basicsStep(icon: String, color: Color, label: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(color.opacity(0.22)).frame(width: 36, height: 36)
                Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func basicsNote(_ text: String, muted: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Color.white.opacity(muted ? 0.2 : 0.4)).frame(width: 4, height: 4).padding(.top, 6)
            Text(text)
                .font(.caption)
                .foregroundStyle(.white.opacity(muted ? 0.75 : 0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Modality card

    private var modalityCard: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 18) {
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 38, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(16)
                    .background(Circle().fill(Color.white.opacity(0.16)))

                Text("How will you train?")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Pick your exercise and we'll show you how to set it up for the best results.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 8) {
                    ForEach(TrainingModality.allCases, id: \.rawValue) { modality in
                        let isSelected = timerViewModel.preferredModality == modality
                        Button { timerViewModel.preferredModality = isSelected ? nil : modality } label: {
                            HStack(spacing: 12) {
                                Image(systemName: modality.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color.white.opacity(isSelected ? 0.25 : 0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(modality.rawValue).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                    Text(modality.tagline).font(.caption).foregroundStyle(.white.opacity(0.85))
                                }
                                Spacer()
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(.white)
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.10))
                            )
                        }

                        if isSelected {
                            VStack(alignment: .leading, spacing: 10) {
                                modalityDetailRow(icon: "gearshape.fill", color: .white.opacity(0.8),
                                                  label: "Setup", text: modality.setup)
                                Divider().background(Color.white.opacity(0.15))
                                modalityDetailRow(icon: "bolt.fill", color: .orange,
                                                  label: "Work (4 min)", text: modality.workPhase)
                                Divider().background(Color.white.opacity(0.15))
                                modalityDetailRow(icon: "heart.fill", color: Color(red: 0.15, green: 0.80, blue: 0.50),
                                                  label: "Rest (3 min)", text: modality.restPhase)
                            }
                            .padding(14)
                            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }

                Button(timerViewModel.preferredModality != nil ? "Let's Go!" : "Skip") { flow.next() }
                    .buttonStyle(OnboardingPrimaryButtonStyle())
                    .padding(.top, 4)
            }
            .padding(28)
            .frame(maxWidth: .infinity)
        }
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func modalityDetailRow(icon: String, color: Color, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.95))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var vo2GoalCard: some View {
        VStack(spacing: 18) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 38, weight: .bold))
                .foregroundStyle(.white)
                .padding(16)
                .background(Circle().fill(Color.white.opacity(0.16)))

            Text("Set a VO₂ max goal")
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)

            Text("We'll draw a target line on your progress chart. Adjust your sex below so the values match your physiology.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            Picker("Biological Sex", selection: $timerViewModel.userBiologicalSexRaw) {
                ForEach(BiologicalSex.allCases, id: \.rawValue) { sex in
                    Text(sex.rawValue).tag(sex.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 8)

            VStack(spacing: 10) {
                ForEach(VO2TargetTier.allCases, id: \.rawValue) { tier in
                    let targetValue = TimerViewModel.vo2TargetValue(
                        age: timerViewModel.userAge,
                        sex: timerViewModel.userBiologicalSex,
                        tier: tier
                    )
                    let isSelected = timerViewModel.vo2TargetTier == tier
                    Button {
                        timerViewModel.vo2TargetTier = tier
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: tier.symbolName)
                                .font(.title3)
                                .frame(width: 28)
                                .foregroundStyle(.white)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(tier.rawValue)
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("\(Int(targetValue)) mL/kg/min")
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.white)
                                }
                                Text(tier.description)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.75))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(.white)
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.08))
                        )
                    }
                }
            }

            VStack(spacing: 12) {
                Button(timerViewModel.vo2TargetTier != nil ? "Set My Goal" : "Skip") {
                    flow.next()
                }
                .buttonStyle(OnboardingPrimaryButtonStyle())

                if timerViewModel.vo2TargetTier != nil {
                    Button("Skip") {
                        timerViewModel.vo2TargetTier = nil
                        flow.next()
                    }
                    .buttonStyle(OnboardingSecondaryButtonStyle())
                }
            }
            .padding(.top, 8)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
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
        .background(Color.black.opacity(0.58), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }

    private func requestNotifications() {
        guard !isRequestingNotificationPermission else { return }
        isRequestingNotificationPermission = true

        timerViewModel.refreshNotificationPermissionState {
            defer { isRequestingNotificationPermission = false }

            switch timerViewModel.notificationPermissionState {
            case .granted:
                timerViewModel.notificationsEnabled = true
                flow.next()
            case .notDetermined, .unknown:
                timerViewModel.notificationsEnabled = true
                timerViewModel.requestNotificationPermission()
                flow.next()
            case .denied, .unavailable:
                flow.next()
            }
        }
    }

    private func saveReminderWeekdayAndContinue() {
        guard !isRequestingNotificationPermission else { return }
        isRequestingNotificationPermission = true

        timerViewModel.refreshNotificationPermissionState {
            defer { isRequestingNotificationPermission = false }
            let hasSelection = !timerViewModel.selectedWeekdaysList.isEmpty

            switch timerViewModel.notificationPermissionState {
            case .granted:
                timerViewModel.notificationsEnabled = true
                if hasSelection {
                    timerViewModel.enableRemindersWithSelectedDays()
                } else {
                    timerViewModel.workoutRemindersEnabled = false
                }
                flow.next()
            case .notDetermined, .unknown:
                timerViewModel.notificationsEnabled = true
                if hasSelection {
                    timerViewModel.enableRemindersWithSelectedDays()
                } else {
                    timerViewModel.workoutRemindersEnabled = false
                }
                timerViewModel.requestNotificationPermission()
                flow.next()
            case .denied, .unavailable:
                timerViewModel.workoutRemindersEnabled = false
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

        // Advance only after the system dialog has been shown and answered,
        // so fetchVO2MaxSamples() has valid auth before it runs.
        timerViewModel.requestHealthKitAuthorizationIfNeeded {
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
