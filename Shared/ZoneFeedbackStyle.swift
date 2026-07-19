// ZoneFeedbackStyle.swift
// Shared between the iOS (N4x4) and watchOS (N4x4Watch) targets.
//
// Presentation for heart-rate zone feedback — colour and copy. Kept separate
// from ZoneFeedback.swift so the decision engine stays pure Foundation (and
// trivially testable); everything that touches SwiftUI or user-facing strings
// lives here, defined once so the phone and Watch can't drift.

import SwiftUI

extension HRZoneStatus {
    /// Semantic tint for colour-coding a heart-rate readout: orange = too low
    /// (speed up), red = too high (slow down), green = in zone.
    /// `nil` means "no target" (warmup/cooldown) — callers supply a neutral
    /// default appropriate to their background.
    var tint: Color? {
        switch self {
        case .below:    return .orange
        case .above:    return .red
        case .inZone:   return .green
        case .noTarget: return nil
        }
    }
}

enum ZoneFeedbackCopy {
    /// Short, glanceable coaching hint for an out-of-zone reading, or `nil` when
    /// in zone / no target. Driven by live status (updates the instant the wearer
    /// crosses the line), unlike the debounced spoken/haptic alerts.
    static func hint(phase: WorkoutPhase, status: HRZoneStatus) -> String? {
        switch (phase, status) {
        case (.highIntensity, .below): return "Push harder"
        case (.highIntensity, .above): return "Ease off"
        case (.rest,          .above): return "Bring it down"
        default:                       return nil
        }
    }
}
