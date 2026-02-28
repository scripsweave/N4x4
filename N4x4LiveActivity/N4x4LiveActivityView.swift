// N4x4LiveActivityView.swift
// Dynamic Island + Lock Screen views for the N4x4 interval timer.

import SwiftUI
import WidgetKit
import ActivityKit

// MARK: - Widget configuration

struct N4x4LiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: N4x4LiveActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(context: context)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(context: context)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(context: context)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(context: context)
                }
            } compactLeading: {
                CompactLeadingView(context: context)
            } compactTrailing: {
                CompactTrailingView(context: context)
            } minimal: {
                MinimalView(context: context)
            }
            .widgetURL(URL(string: "n4x4://open"))
            .keylineTint(context.state.phase.color)
        }
    }
}

// MARK: - Compact (phone in use, another app in foreground)

/// Left slot: phase icon + "HIT 2/4"
struct CompactLeadingView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: context.state.phase.symbolName)
                .font(.caption2.bold())
                .foregroundStyle(phaseColor)
            if context.state.phase == .highIntensity {
                Text("\(context.state.phase.shortLabel) \(context.state.currentInterval)/\(context.state.totalIntervals)")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            } else {
                Text(context.state.phase.shortLabel)
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            }
        }
        .padding(.leading, 4)
    }

    var phaseColor: Color { context.state.phase.color }
}

/// Right slot: live countdown or paused indicator
struct CompactTrailingView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>

    var body: some View {
        Group {
            if context.state.isRunning {
                Text(timerInterval: Date.now...context.state.intervalEndTime, countsDown: true)
                    .monospacedDigit()
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "pause.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, 4)
    }
}

/// Minimal: shown when two Live Activities are active simultaneously
struct MinimalView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>

    var body: some View {
        if context.state.isRunning {
            Text(timerInterval: Date.now...context.state.intervalEndTime, countsDown: true)
                .monospacedDigit()
                .font(.caption2.bold())
                .foregroundStyle(context.state.phase.color)
        } else {
            Image(systemName: context.state.phase.symbolName)
                .font(.caption2)
                .foregroundStyle(context.state.phase.color)
        }
    }
}

// MARK: - Expanded (user long-presses the Dynamic Island)

/// Top-left: phase icon + name
struct ExpandedLeadingView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: context.state.phase.symbolName)
                .font(.title3.bold())
                .foregroundStyle(context.state.phase.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(context.state.intervalName)
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                if context.state.phase == .highIntensity {
                    Text("Interval \(context.state.currentInterval) of \(context.state.totalIntervals)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.leading, 8)
    }
}

/// Top-right: interval progress dots
struct ExpandedTrailingView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>

    var body: some View {
        Group {
            if context.state.phase == .cooldown {
                Text("Cooldown")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                IntervalDotsView(
                    current: context.state.currentInterval,
                    total: context.state.totalIntervals,
                    color: context.state.phase.color
                )
            }
        }
        .padding(.trailing, 8)
    }
}

/// Center: large countdown timer
struct ExpandedCenterView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>

    var body: some View {
        if context.state.isRunning {
            Text(timerInterval: Date.now...context.state.intervalEndTime, countsDown: true)
                .monospacedDigit()
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .foregroundStyle(context.state.phase.color)
                .minimumScaleFactor(0.7)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "pause.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Paused")
                    .font(.title2.bold())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Bottom: HR zone target
struct ExpandedBottomView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>

    var body: some View {
        if context.state.hrLow > 0 && context.state.hrHigh > 0 {
            Text("Target: \(context.state.hrLow)–\(context.state.hrHigh) bpm")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        } else {
            Text("Easy effort")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 4)
        }
    }
}

// MARK: - Lock Screen / StandBy / Notification Banner

struct LockScreenView: View {
    let context: ActivityViewContext<N4x4LiveActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Left column: icon + timer
            VStack(alignment: .leading, spacing: 4) {
                Image(systemName: context.state.phase.symbolName)
                    .font(.title2.bold())
                    .foregroundStyle(context.state.phase.color)

                if context.state.isRunning {
                    Text(timerInterval: Date.now...context.state.intervalEndTime, countsDown: true)
                        .monospacedDigit()
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.7)
                } else {
                    Text("Paused")
                        .font(.title2.bold())
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Right column: interval name + HR target + dots
            VStack(alignment: .trailing, spacing: 6) {
                if context.state.phase == .highIntensity {
                    Text("\(context.state.phase.shortLabel) \(context.state.currentInterval)/\(context.state.totalIntervals)")
                        .font(.headline)
                        .foregroundStyle(.white)
                } else {
                    Text(context.state.intervalName)
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                if context.state.hrLow > 0 && context.state.hrHigh > 0 {
                    Text("\(context.state.hrLow)–\(context.state.hrHigh) bpm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Easy effort")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if context.state.phase == .cooldown {
                    Text("Cooldown")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    IntervalDotsView(
                        current: context.state.currentInterval,
                        total: context.state.totalIntervals,
                        color: context.state.phase.color
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Shared subview

/// ●●○○ progress dots, one per HIT interval
struct IntervalDotsView: View {
    let current: Int
    let total: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            ForEach(1...max(1, total), id: \.self) { i in
                Circle()
                    .fill(i <= current ? color : Color.white.opacity(0.25))
                    .frame(width: 8, height: 8)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
extension N4x4LiveActivityAttributes {
    static var preview: N4x4LiveActivityAttributes {
        N4x4LiveActivityAttributes(workoutStartTime: Date())
    }
}

extension N4x4LiveActivityAttributes.ContentState {
    static var hitPreview: N4x4LiveActivityAttributes.ContentState {
        N4x4LiveActivityAttributes.ContentState(
            intervalName: "High Intensity",
            phase: .highIntensity,
            intervalEndTime: Date().addingTimeInterval(154),
            isRunning: true,
            currentInterval: 2,
            totalIntervals: 4,
            hrLow: 161,
            hrHigh: 181
        )
    }

    static var restPreview: N4x4LiveActivityAttributes.ContentState {
        N4x4LiveActivityAttributes.ContentState(
            intervalName: "Recovery",
            phase: .rest,
            intervalEndTime: Date().addingTimeInterval(98),
            isRunning: true,
            currentInterval: 2,
            totalIntervals: 4,
            hrLow: 119,
            hrHigh: 133
        )
    }
}

#Preview("Lock Screen — HIT", as: .content,
         using: N4x4LiveActivityAttributes.preview) {
    N4x4LiveActivityWidget()
} contentStates: {
    N4x4LiveActivityAttributes.ContentState.hitPreview
    N4x4LiveActivityAttributes.ContentState.restPreview
}
#endif
