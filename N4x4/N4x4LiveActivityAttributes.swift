// N4x4LiveActivityAttributes.swift
// Shared between the main app target and the N4x4LiveActivity widget extension.
// Both targets must include this file (set via Xcode target membership).

#if canImport(ActivityKit)
import ActivityKit
#endif
import Foundation
import SwiftUI

// MARK: - ActivityAttributes
// ActivityKit does not exist on watchOS. The Watch target shares this file only
// for the WorkoutPhase enum below, so the attributes type is compiled out there.

#if canImport(ActivityKit)
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
        /// Live heart rate (bpm) from the active source, or 0 when none is
        /// streaming. Defaulted so older encoded states still decode.
        var currentHR: Int = 0
        var appearanceRaw: String? = nil
    }

    // Static — set once when the activity starts, never changes mid-workout.
    var workoutStartTime: Date
}

extension N4x4LiveActivityAttributes.ContentState {
    /// The extension may render an old state after its end time, before the
    /// phone update/removal arrives. ClosedRange traps if lower > upper.
    func countdownRange(at now: Date = Date()) -> ClosedRange<Date> {
        now...max(now, intervalEndTime)
    }

    var appearance: AppAppearance { AppAppearance(storedValue: appearanceRaw) }
    var phaseColor: Color { phase.color(appearance: appearance) }

    /// Whether a live heart rate is currently streaming.
    var hasLiveHR: Bool { currentHR > 0 }

    /// Colour for the live HR readout: orange below the target zone, red above,
    /// green inside — matching the in-app zone colours (see ZoneFeedbackStyle).
    /// White when there is no reading or no target to compare against.
    var liveHRColor: Color {
        guard currentHR > 0 else { return .white }
        if hrLow > 0 && currentHR < hrLow { return Color(red: 1.0, green: 0.58, blue: 0.0) }
        if hrHigh > 0 && currentHR > hrHigh { return Color(red: 1.0, green: 0.23, blue: 0.19) }
        return Color(red: 0.20, green: 0.78, blue: 0.55)
    }
}
#endif

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
        case .warmup:        return Color(red: 0.18,  green: 0.52,  blue: 1.0)
        case .highIntensity: return Color(red: 1.0,   green: 0.58,  blue: 0.0)   // amber (matches phone/brand)
        case .rest:          return Color(red: 0.20,  green: 0.78,  blue: 0.55)
        case .cooldown:      return Color(red: 0.20,  green: 0.75,  blue: 0.85)
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

// MARK: - Appearance shared by phone, Watch and Live Activity

enum AppAppearance: String, CaseIterable, Identifiable {
    case standard
    case fall

    static let storageKey = "appAppearanceRaw"
    init(storedValue: String?) { self = Self(rawValue: storedValue ?? "") ?? .standard }
    var id: String { rawValue }
    var title: String { self == .fall ? "Fall Colors" : "Default" }
}

extension EnvironmentValues {
    @Entry var appAppearance: AppAppearance = .standard
}

extension AppAppearance {
    var accent: Color {
        self == .fall ? Color(red: 0.94, green: 0.61, blue: 0.35) : Color(red: 0.18, green: 0.52, blue: 1.0)
    }
    var workAccent: Color {
        self == .fall ? Color(red: 1.0, green: 0.70, blue: 0.30) : Color(red: 1.0, green: 0.58, blue: 0.0)
    }
    var recoveryAccent: Color {
        self == .fall ? Color(red: 0.85, green: 0.47, blue: 0.34) : Color(red: 0.20, green: 0.78, blue: 0.55)
    }
    var cooldownAccent: Color {
        self == .fall ? Color(red: 0.87, green: 0.65, blue: 0.48) : Color(red: 0.20, green: 0.75, blue: 0.85)
    }
    var background: Color {
        self == .fall ? Color(red: 0.055, green: 0.035, blue: 0.030) : Color(red: 0.04, green: 0.04, blue: 0.05)
    }
    var surface: Color {
        self == .fall ? Color(red: 0.12, green: 0.075, blue: 0.060) : Color(red: 0.09, green: 0.10, blue: 0.12)
    }
    var surfaceRaised: Color {
        self == .fall ? Color(red: 0.18, green: 0.11, blue: 0.085) : Color(red: 0.13, green: 0.14, blue: 0.16)
    }
    var brandGlow: AngularGradient {
        AngularGradient(colors: [accent, workAccent, accent], center: .center,
                        startAngle: .degrees(90), endAngle: .degrees(450))
    }
    init(payload: [String: Any]) { self.init(storedValue: payload[Self.storageKey] as? String) }
}

extension WorkoutPhase {
    /// Decorative phase colors; heart-rate status colors remain independent.
    func color(appearance: AppAppearance) -> Color {
        switch self {
        case .warmup: return appearance.accent
        case .highIntensity: return appearance.workAccent
        case .rest: return appearance.recoveryAccent
        case .cooldown: return appearance.cooldownAccent
        }
    }
}
