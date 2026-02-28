// N4x4LiveActivityAttributes.swift
// Shared between the main app target and the N4x4LiveActivity widget extension.
// Both targets must include this file (set via Xcode target membership).

import ActivityKit
import Foundation
import SwiftUI

// MARK: - ActivityAttributes

struct N4x4LiveActivityAttributes: ActivityAttributes {

    // Dynamic state — updated on every interval change and pause/resume.
    struct ContentState: Codable, Hashable {
        /// Human-readable name, e.g. "High Intensity", "Recovery", "Warmup"
        var intervalName: String
        /// Phase drives color, icon, and HR zone copy in the widget views.
        var phase: WorkoutPhase
        /// The wall-clock time when the current interval ends.
        /// Widget views use Text(timerInterval:) so iOS counts down natively
        /// without requiring per-second updates from the app.
        var intervalEndTime: Date
        /// False when paused — widget shows a frozen display instead of a live timer.
        var isRunning: Bool
        /// 1-based count of the current HIT interval (e.g. 2 out of 4).
        /// For warmup/rest phases this reflects the *next* HIT number.
        var currentInterval: Int
        /// Total number of HIT intervals in the workout (e.g. 4).
        var totalIntervals: Int
        /// Lower bound of the target HR zone for the current phase (bpm).
        var hrLow: Int
        /// Upper bound of the target HR zone for the current phase (bpm).
        var hrHigh: Int
    }

    // Static — set once when the activity starts, never changes mid-workout.
    var workoutStartTime: Date
}

// MARK: - WorkoutPhase

/// Drives colour, icon, and label in Live Activity / Dynamic Island views.
enum WorkoutPhase: String, Codable, Hashable {
    case warmup
    case highIntensity
    case rest
    case cooldown

    /// Phase colour — hardcoded so it works in both the app and the widget extension
    /// without requiring Assets.xcassets to be added to the extension bundle.
    var color: Color {
        switch self {
        case .warmup:        return Color(red: 0.227, green: 0.525, blue: 1.0)
        case .highIntensity: return Color(red: 1.0,   green: 0.227, blue: 0.361)
        case .rest:          return Color(red: 0.188, green: 0.820, blue: 0.345)
        case .cooldown:      return Color(red: 0.0,   green: 0.76,  blue: 0.80)
        }
    }

    /// Short label shown in compact Dynamic Island and dots.
    var shortLabel: String {
        switch self {
        case .warmup:        return "Warm Up"
        case .highIntensity: return "HIT"
        case .rest:          return "Rest"
        case .cooldown:      return "Cool"
        }
    }

    /// SF Symbol name for phase icon.
    var symbolName: String {
        switch self {
        case .warmup:        return "figure.walk"
        case .highIntensity: return "bolt.fill"
        case .rest:          return "heart.fill"
        case .cooldown:      return "wind"
        }
    }
}
