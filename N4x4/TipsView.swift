// TipsView.swift

import SwiftUI

// MARK: - Mode

enum TipsMode: CaseIterable {
    case basics, exercise, beginner, advanced

    var label: String {
        switch self {
        case .basics:   return "Protocol"
        case .exercise: return "Exercise"
        case .beginner: return "Beginner"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .basics:   return "doc.text.fill"
        case .exercise: return "figure.run"
        case .beginner: return "figure.walk"
        case .advanced: return "bolt.heart.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .basics:   return Color(red: 0.35, green: 0.60, blue: 1.00)
        case .exercise: return Color(red: 0.10, green: 0.80, blue: 0.65)
        case .beginner: return Color(red: 0.15, green: 0.80, blue: 0.50)
        case .advanced: return Color(red: 1.00, green: 0.38, blue: 0.22)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .basics:
            return [.black, Color(red: 0.10, green: 0.20, blue: 0.55).opacity(0.75), .black]
        case .exercise:
            return [.black, Color(red: 0.05, green: 0.40, blue: 0.35).opacity(0.75), .black]
        case .beginner:
            return [.black, Color(red: 0.05, green: 0.45, blue: 0.30).opacity(0.75), .black]
        case .advanced:
            return [.black, Color(red: 0.55, green: 0.12, blue: 0.05).opacity(0.75), .black]
        }
    }

    var tagline: String {
        switch self {
        case .basics:   return "Understand the science behind the protocol."
        case .exercise: return "Set up your chosen activity for maximum results."
        case .beginner: return "Build your foundation. Consistency over intensity."
        case .advanced: return "Push from good to elite with precision."
        }
    }
}

// MARK: - Tip data

private struct Tip: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let body: String
}

private let beginnerTips: [Tip] = [
    Tip(icon: "bubble.left.fill",       title: "Find Your Talking Pace",
        body: "During the 4-minute work phase, you should only be able to manage one or two-word grunts. Full sentences? Not hard enough. Gasping and dizzy? Back it off. That uncomfortable middle ground is your target zone."),
    Tip(icon: "tortoise.fill",          title: "Don't Sprint the Start",
        body: "The most common beginner mistake: sprint the first 60 seconds, then crash before 4 minutes are up. Aim for a steady, hard grind — like a fast uphill walk or controlled run — that you can hold consistently for the full duration."),
    Tip(icon: "lungs.fill",             title: "Respect the 3-Minute Rest",
        body: "In the beginning, recovery is just as important as the work. Breathe deeply and bring your heart rate down during rest. If you can't start the next set after 3 minutes, lower the intensity of your work phase next time."),
    Tip(icon: "dial.low.fill",          title: "Start with 2 or 3 Sets",
        body: "You don't need to complete all 4 sets on day one. Start with two 4-minute intervals and add one set per week. Building gradually prevents burnout and injury."),
    Tip(icon: "bicycle",                title: "Choose the Right Activity",
        body: "Running is high-impact and can cause shin splints for beginners. A stationary bike or elliptical at high incline lets you hit the same heart rates with far less joint stress while you build your base."),
    Tip(icon: "flame.fill",             title: "Always Warm Up for 10 Minutes",
        body: "Never jump straight into a 4×4. Spend at least 10 minutes doing a very light version of your exercise first. This wakes up your lungs, raises core temperature, and lubricates your joints before the real effort begins."),
    Tip(icon: "calendar.badge.checkmark", title: "Once a Week is Enough to Start",
        body: "Begin with just one session per week. Once your body stops feeling crushed the next day, add a second. Two sessions a week deliver massive cardiovascular improvements without the injury risk of doing more."),
]

private let advancedTips: [Tip] = [
    Tip(icon: "arrow.up.heart.fill",    title: "Ramp Up Gradually",
        body: "Don't expect to hit peak heart rate in the first 30 seconds. Use the opening 90 seconds to climb steadily into the 85–95% max HR zone, then hold it there for the remaining 2.5 minutes. Spiking too fast leads to early fatigue."),
    Tip(icon: "figure.walk",            title: "Keep Recovery Active",
        body: "A full stop during rest makes it far harder for your heart rate to climb back up in the next set. Keep moving and aim to hold around 60–70% max HR — staying primed rather than fully cooling down."),
    Tip(icon: "timer",                  title: "Chase Accumulated Time at Peak",
        body: "The real goal is to spend at least 8–12 minutes total across all four sets above 90% max HR. If you only reach that zone in the final few seconds of each set, you're not accumulating enough time at VO₂ max."),
    Tip(icon: "waveform.path.ecg",      title: "Account for Cardiac Drift",
        body: "By the third and fourth intervals, your heart rate will naturally stay elevated even if your pace drops. Trust your HR monitor over speed or power output to avoid over-taxing yourself or leaving gains on the table."),
    Tip(icon: "fork.knife",             title: "Fuel Before You Train",
        body: "High-intensity work runs on glycogen — you can't go all-out fasted or on very low carbs. Have fast-acting carbohydrates (a banana, honey, or fruit) 30–60 minutes before training to ensure you can reach peak intensities."),
    Tip(icon: "moon.zzz.fill",          title: "Respect the 48-Hour Rule",
        body: "The 4×4 stresses your heart's stroke volume significantly. Never do it on back-to-back days. Your VO₂ max gains — the cardiac remodelling — happen during the recovery window, not during the workout itself."),
    Tip(icon: "exclamationmark.triangle.fill", title: "Recognise a Plateau Early",
        body: "If you're giving maximum effort but can no longer reach your target heart rate, your nervous system is likely overreached. Take 3–5 days of full rest or easy walking, then return refreshed."),
]

// MARK: - Main view

struct TipsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("preferredModalityRaw") private var preferredModalityRaw: String = ""
    @State private var selectedMode: TipsMode = .basics
    @State private var selectedModality: TrainingModality? = nil

    var body: some View {
        ZStack(alignment: .top) {
            // Animated background
            LinearGradient(colors: selectedMode.gradientColors,
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.4), value: selectedMode)

            ScrollView {
                VStack(spacing: 0) {
                    Color.clear.frame(height: 72) // space for floating header

                    // Mode grid
                    modeGrid
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 6)

                    // Tagline
                    Text(selectedMode.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)
                        .id(selectedMode.tagline)
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.2), value: selectedMode)

                    // Content
                    Group {
                        switch selectedMode {
                        case .basics:
                            basicsContent
                        case .exercise:
                            exerciseContent
                        case .beginner:
                            tipsList(beginnerTips, accent: TipsMode.beginner.accentColor)
                        case .advanced:
                            tipsList(advancedTips, accent: TipsMode.advanced.accentColor)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                    .animation(.easeInOut(duration: 0.25), value: selectedMode)
                }
            }

            // Floating header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: selectedMode.icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(selectedMode.accentColor)
                        .animation(.easeInOut(duration: 0.25), value: selectedMode)
                    Text("4×4 Training Guide")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                Spacer()
                Button("Done") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)
            .background(.ultraThinMaterial.opacity(0.55))
        }
        .onAppear {
            selectedModality = TrainingModality(rawValue: preferredModalityRaw)
        }
    }

    // MARK: - Mode grid (2 × 2)

    private var modeGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(TipsMode.allCases, id: \.label) { mode in
                let isSelected = selectedMode == mode
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedMode = mode
                    }
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: mode.icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(isSelected ? mode.accentColor : .white.opacity(0.5))
                        Text(mode.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? .white : .white.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(isSelected ? mode.accentColor.opacity(0.22) : Color.white.opacity(0.07))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(isSelected ? mode.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Protocol basics

    private var basicsContent: some View {
        VStack(spacing: 12) {
            // Visual timeline
            VStack(spacing: 0) {
                protocolStep(icon: "figure.walk", color: Color(red: 0.35, green: 0.60, blue: 1.0),
                             label: "Warm-up", detail: "5 minutes · Easy, increasing pace", isLast: false)
                connector
                protocolStep(icon: "bolt.fill", color: .orange,
                             label: "Work Hard", detail: "4 minutes · 85–95% max heart rate", isLast: false)
                connector
                protocolStep(icon: "heart.fill", color: Color(red: 0.15, green: 0.80, blue: 0.50),
                             label: "Active Rest", detail: "3 minutes · 60–70% max heart rate", isLast: false)
                connector
                repeatBadge
                connector
                protocolStep(icon: "figure.walk.motion", color: .cyan,
                             label: "Cool-down", detail: "5 minutes · Light movement", isLast: true)
            }
            .padding(18)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16))

            // Key notes
            infoCard(title: "For Beginners", icon: "figure.walk", color: Color(red: 0.15, green: 0.80, blue: 0.50)) {
                noteRow("Can't speak in full sentences? You're at the right intensity.")
                noteRow("Start with 2 intervals and build up to 4 over several weeks.")
                noteRow("A stationary bike or elliptical reduces joint impact when starting out.")
            }

            infoCard(title: "Advanced Notes", icon: "bolt.heart.fill", color: .orange) {
                noteRow("Use a heart rate monitor to stay in the 85–95% max HR zone.")
                noteRow("Allow 48–72 hours of recovery between sessions.")
                noteRow("Eat carbohydrates 30–60 minutes before training to fuel peak intensity.")
            }

            // Golden rule
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.yellow)
                    .font(.subheadline)
                Text("If you can't finish the 4th minute of the 4th set, intensity was too high. If you aren't breathing heavily by the 2nd minute, it was too low.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            // Disclaimer
            Text("⚠️  High-intensity exercise places significant stress on the cardiovascular system. Consult a healthcare professional before starting, especially if you have pre-existing health conditions.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func protocolStep(icon: String, color: Color, label: String, detail: String, isLast: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                Text(detail).font(.caption).foregroundStyle(.white.opacity(0.65))
            }
            Spacer()
        }
    }

    private var connector: some View {
        HStack {
            Spacer().frame(width: 20)
            Rectangle()
                .fill(Color.white.opacity(0.15))
                .frame(width: 1.5, height: 10)
                .padding(.leading, 19)
            Spacer()
        }
    }

    private var repeatBadge: some View {
        HStack(spacing: 8) {
            Spacer().frame(width: 20)
            Image(systemName: "arrow.clockwise")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.6))
            Text("Repeat Work + Rest × 4 times total")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer()
        }
        .padding(.leading, 8)
    }

    // MARK: - Exercise / modalities

    private var exerciseContent: some View {
        VStack(spacing: 12) {
            // Modality picker
            VStack(spacing: 8) {
                ForEach(TrainingModality.allCases, id: \.rawValue) { modality in
                    let isSelected = selectedModality == modality
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedModality = isSelected ? nil : modality
                            preferredModalityRaw = isSelected ? "" : modality.rawValue
                        }
                    } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(TipsMode.exercise.accentColor.opacity(isSelected ? 0.25 : 0.10))
                                    .frame(width: 40, height: 40)
                                Image(systemName: modality.icon)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(TipsMode.exercise.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(modality.rawValue)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                Text(modality.tagline)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Image(systemName: isSelected ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(isSelected ? TipsMode.exercise.accentColor.opacity(0.18) : Color.white.opacity(0.07))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(isSelected ? TipsMode.exercise.accentColor.opacity(0.45) : Color.clear, lineWidth: 1.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)

                    // Inline detail expansion
                    if isSelected {
                        modalityDetail(modality)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
            }

            // Golden rule
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "stopwatch.fill")
                    .foregroundStyle(TipsMode.exercise.accentColor)
                    .font(.subheadline)
                Text("Can't finish the 4th minute of the 4th set? Too intense. Not breathing heavily by the 2nd minute? Not intense enough.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .background(TipsMode.exercise.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func modalityDetail(_ modality: TrainingModality) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            detailSection(icon: "gearshape.fill", color: .white.opacity(0.85), label: "Setup", text: modality.setup)
            Divider().background(Color.white.opacity(0.1))
            detailSection(icon: "bolt.fill", color: .orange, label: "Work — 4 min", text: modality.workPhase)
            Divider().background(Color.white.opacity(0.1))
            detailSection(icon: "heart.fill", color: TipsMode.exercise.accentColor, label: "Rest — 3 min", text: modality.restPhase)
        }
        .padding(16)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
        .padding(.top, -4)
    }

    private func detailSection(icon: String, color: Color, label: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)
        }
    }

    // MARK: - Tips list (beginner / advanced)

    private func tipsList(_ tips: [Tip], accent: Color) -> some View {
        VStack(spacing: 14) {
            ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                TipCard(tip: tip, number: index + 1, accent: accent)
            }
        }
    }

    // MARK: - Shared helpers

    private func infoCard<Content: View>(title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(color)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
    }

    private func noteRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(Color.white.opacity(0.3)).frame(width: 4, height: 4).padding(.top, 6)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Tip card

private struct TipCard: View {
    let tip: Tip
    let number: Int
    let accent: Color

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack {
                Circle().fill(accent.opacity(0.18)).frame(width: 48, height: 48)
                Image(systemName: tip.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(number).").font(.caption.weight(.bold)).foregroundStyle(accent)
                    Text(tip.title).font(.headline).foregroundStyle(.white)
                }
                Text(tip.body)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.80))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(accent.opacity(0.22), lineWidth: 1)
                )
        )
    }
}
