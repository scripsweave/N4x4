// TipsView.swift

import SwiftUI

// MARK: - Data

private struct Tip: Identifiable {
    let id = UUID()
    let icon: String
    let color: Color
    let title: String
    let body: String
}

private let tips: [Tip] = [
    Tip(
        icon: "arrow.up.heart.fill",
        color: Color(red: 1.0, green: 0.35, blue: 0.25),
        title: "Ramp Up Gradually",
        body: "Don't expect to hit peak heart rate in the first 30 seconds. Use the opening 90 seconds of each interval to climb steadily into the 85–95% max HR zone, then hold it there for the remaining 2.5 minutes. Spiking too fast leads to early fatigue."
    ),
    Tip(
        icon: "figure.walk",
        color: Color(red: 0.2, green: 0.6, blue: 1.0),
        title: "Keep Recovery Active",
        body: "A full stop during rest makes it far harder for your heart rate to climb back up in the next set. Keep moving at an easy pace and aim to hold around 60–70% of max HR — staying primed rather than fully cooling down."
    ),
    Tip(
        icon: "timer",
        color: Color(red: 0.18, green: 0.82, blue: 0.35),
        title: "Chase Accumulated Time at Peak",
        body: "The real goal is to spend at least 8–12 minutes total across all four sets above 90% max HR. If you only reach that zone in the final few seconds of each set, you're not accumulating enough time at VO₂ max to drive adaptation."
    ),
    Tip(
        icon: "waveform.path.ecg",
        color: Color(red: 0.7, green: 0.35, blue: 1.0),
        title: "Account for Cardiac Drift",
        body: "By the third and fourth intervals, your heart rate will naturally stay elevated even if your pace drops. That's normal — it's called cardiac drift. Trust your HR monitor over speed or power output so you don't over-tax yourself or leave gains on the table."
    ),
    Tip(
        icon: "fork.knife",
        color: Color(red: 1.0, green: 0.75, blue: 0.1),
        title: "Fuel Before You Train",
        body: "High-intensity work runs on glycogen — you can't go all-out in a fasted state or on very low carbs. Have some fast-acting carbohydrates (a banana, some honey, or a piece of fruit) 30–60 minutes before training to ensure you can actually reach those peak intensities."
    ),
    Tip(
        icon: "moon.zzz.fill",
        color: Color(red: 0.35, green: 0.45, blue: 1.0),
        title: "Respect the 48-Hour Rule",
        body: "The 4x4 is demanding enough to stress your heart's stroke volume significantly. Never do it on back-to-back days. Your fitness gains — the cardiac remodelling that raises your VO₂ max — happen during the recovery window, not during the workout itself."
    ),
    Tip(
        icon: "exclamationmark.triangle.fill",
        color: Color(red: 1.0, green: 0.5, blue: 0.1),
        title: "Recognise a Plateau Early",
        body: "If you're giving maximum effort but can no longer reach your target heart rate, your nervous system is likely overreached. Don't push harder — take 3–5 days of full rest or easy walking to let your body recover, then return refreshed."
    ),
]

// MARK: - View

struct TipsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.55), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    // Header
                    VStack(spacing: 10) {
                        Image(systemName: "bolt.heart.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(18)
                            .background(Circle().fill(Color.white.opacity(0.14)))

                        Text("Advanced 4×4 Tips")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Techniques to push from good to elite.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .padding(.horizontal, 24)

                    // Tip cards
                    VStack(spacing: 14) {
                        ForEach(Array(tips.enumerated()), id: \.element.id) { index, tip in
                            TipCard(tip: tip, number: index + 1)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }

            // Done button pinned to top-right
            VStack {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 16)
                        .padding(.trailing, 20)
                }
                Spacer()
            }
        }
    }
}

// MARK: - Tip card

private struct TipCard: View {
    let tip: Tip
    let number: Int

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon column
            ZStack {
                Circle()
                    .fill(tip.color.opacity(0.2))
                    .frame(width: 48, height: 48)
                Image(systemName: tip.icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tip.color)
            }
            .padding(.top, 2)

            // Text column
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("\(number).")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tip.color)
                    Text(tip.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                }
                Text(tip.body)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(3)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(tip.color.opacity(0.25), lineWidth: 1)
                )
        )
    }
}
