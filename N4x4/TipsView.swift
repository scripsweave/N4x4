// TipsView.swift

import SwiftUI

// MARK: - Level

enum TipLevel: CaseIterable {
    case beginner, advanced

    var label: String {
        switch self {
        case .beginner: return "Beginner"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .beginner: return "figure.walk"
        case .advanced: return "bolt.heart.fill"
        }
    }

    var accentColor: Color {
        switch self {
        case .beginner: return Color(red: 0.15, green: 0.80, blue: 0.50)
        case .advanced: return Color(red: 1.00, green: 0.38, blue: 0.22)
        }
    }

    var gradientColors: [Color] {
        switch self {
        case .beginner:
            return [Color.black, Color(red: 0.05, green: 0.45, blue: 0.30).opacity(0.70), Color.black]
        case .advanced:
            return [Color.black, Color(red: 0.55, green: 0.12, blue: 0.05).opacity(0.70), Color.black]
        }
    }

    var tagline: String {
        switch self {
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
    Tip(
        icon: "bubble.left.fill",
        title: "Find Your Talking Pace",
        body: "During the 4-minute work phase, you should only be able to manage one or two-word grunts. Full sentences? Not hard enough. Gasping and dizzy? Back it off. That uncomfortable middle ground is your target zone."
    ),
    Tip(
        icon: "tortoise.fill",
        title: "Don't Sprint the Start",
        body: "The most common beginner mistake: sprint the first 60 seconds, then crash before the 4 minutes are up. Aim for a steady, hard grind — like a fast uphill walk or a controlled run — that you can hold consistently for the full duration."
    ),
    Tip(
        icon: "lungs.fill",
        title: "Respect the 3-Minute Rest",
        body: "In the beginning, recovery is just as important as the work. Breathe deeply and bring your heart rate down during rest. If you can't start the next set after 3 minutes, lower the intensity of your work phase next time — not the rest time."
    ),
    Tip(
        icon: "dial.low.fill",
        title: "Start with 2 or 3 Sets",
        body: "You don't need to complete all 4 sets on day one. Start with two 4-minute intervals and add one set per week until you can complete the full cycle. Building gradually prevents burnout and injury."
    ),
    Tip(
        icon: "bicycle",
        title: "Choose the Right Activity",
        body: "Running is high-impact and can cause shin splints for beginners. Consider a stationary bike or elliptical at high incline — you'll hit the same heart rates with far less stress on your joints while you build a base."
    ),
    Tip(
        icon: "flame.fill",
        title: "Always Warm Up for 10 Minutes",
        body: "Never jump straight into a 4×4. Spend at least 10 minutes doing a very light version of your chosen exercise first. This wakes up your lungs, raises your core temperature, and lubricates your joints before the real effort begins."
    ),
    Tip(
        icon: "calendar.badge.checkmark",
        title: "Once a Week is Enough to Start",
        body: "Begin with just one session per week. Once your body stops feeling crushed the next day, add a second. For most beginners, two sessions a week deliver massive cardiovascular improvements without the injury risk of doing more."
    ),
]

private let advancedTips: [Tip] = [
    Tip(
        icon: "arrow.up.heart.fill",
        title: "Ramp Up Gradually",
        body: "Don't expect to hit peak heart rate in the first 30 seconds. Use the opening 90 seconds of each interval to climb steadily into the 85–95% max HR zone, then hold it there for the remaining 2.5 minutes. Spiking too fast leads to early fatigue."
    ),
    Tip(
        icon: "figure.walk",
        title: "Keep Recovery Active",
        body: "A full stop during rest makes it far harder for your heart rate to climb back up in the next set. Keep moving at an easy pace and aim to hold around 60–70% of max HR — staying primed rather than fully cooling down."
    ),
    Tip(
        icon: "timer",
        title: "Chase Accumulated Time at Peak",
        body: "The real goal is to spend at least 8–12 minutes total across all four sets above 90% max HR. If you only reach that zone in the final few seconds of each set, you're not accumulating enough time at VO₂ max to drive adaptation."
    ),
    Tip(
        icon: "waveform.path.ecg",
        title: "Account for Cardiac Drift",
        body: "By the third and fourth intervals, your heart rate will naturally stay elevated even if your pace drops. That's normal — it's called cardiac drift. Trust your HR monitor over speed or power output to avoid over-taxing yourself or leaving gains on the table."
    ),
    Tip(
        icon: "fork.knife",
        title: "Fuel Before You Train",
        body: "High-intensity work runs on glycogen — you can't go all-out fasted or on very low carbs. Have some fast-acting carbohydrates (a banana, honey, or fruit) 30–60 minutes before training to ensure you can actually reach peak intensities."
    ),
    Tip(
        icon: "moon.zzz.fill",
        title: "Respect the 48-Hour Rule",
        body: "The 4×4 stresses your heart's stroke volume significantly. Never do it on back-to-back days. Your fitness gains — the cardiac remodelling that raises your VO₂ max — happen during the recovery window, not during the workout itself."
    ),
    Tip(
        icon: "exclamationmark.triangle.fill",
        title: "Recognise a Plateau Early",
        body: "If you're giving maximum effort but can no longer reach your target heart rate, your nervous system is likely overreached. Don't push harder — take 3–5 days of full rest or easy walking to let your body recover, then return refreshed."
    ),
]

// MARK: - Main view

struct TipsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLevel: TipLevel = .beginner
    @Namespace private var levelIndicator

    fileprivate var tips: [Tip] { selectedLevel == .beginner ? beginnerTips : advancedTips }

    var body: some View {
        ZStack(alignment: .top) {
            // Animated background
            LinearGradient(
                colors: selectedLevel.gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.4), value: selectedLevel)

            ScrollView {
                VStack(spacing: 0) {
                    // Top spacer for the fixed header
                    Color.clear.frame(height: 140)

                    // Level switcher card + tagline
                    VStack(spacing: 10) {
                        levelSwitcher
                        Text(selectedLevel.tagline)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.65))
                            .multilineTextAlignment(.center)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                            .id(selectedLevel.tagline)
                            .animation(.easeInOut(duration: 0.25), value: selectedLevel)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)

                    // Tip cards
                    VStack(spacing: 14) {
                        ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                            TipCard(tip: tip, number: index + 1, accent: selectedLevel.accentColor)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                    .animation(.easeInOut(duration: 0.30), value: selectedLevel)
                }
            }

            // Fixed floating header
            VStack(spacing: 0) {
                HStack(alignment: .center) {
                    // Animated icon + title
                    HStack(spacing: 10) {
                        Image(systemName: selectedLevel.icon)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(selectedLevel.accentColor)
                            .animation(.easeInOut(duration: 0.3), value: selectedLevel)
                        Text("4×4 Tips")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                    }

                    Spacer()

                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 16)
                .background(.ultraThinMaterial.opacity(0.6))
            }
        }
    }

    // MARK: - Level switcher

    private var levelSwitcher: some View {
        HStack(spacing: 0) {
            ForEach(TipLevel.allCases, id: \.label) { level in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        selectedLevel = level
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: level.icon)
                            .font(.system(size: 13, weight: .semibold))
                        Text(level.label)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundStyle(selectedLevel == level ? .black : .white.opacity(0.6))
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background {
                        if selectedLevel == level {
                            Capsule()
                                .fill(level.accentColor)
                                .matchedGeometryEffect(id: "pill", in: levelIndicator)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
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
                Circle()
                    .fill(accent.opacity(0.18))
                    .frame(width: 48, height: 48)
                Image(systemName: tip.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(accent)
            }
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(number).")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(accent)
                    Text(tip.title)
                        .font(.headline)
                        .foregroundStyle(.white)
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
