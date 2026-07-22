// WatchMessage.swift
// Shared between the iOS (N4x4) and watchOS (N4x4Watch) targets.
// All WCSession dictionary keys and message-type constants live here.
// No logic — only static string constants.

import Foundation

enum WatchMessageKey {

    // Every message must include this key.
    static let messageType          = "type"

    // ── Commands: Watch → Phone ──────────────────────────────
    static let cmdStartPause        = "cmd_startPause"
    static let cmdSkip              = "cmd_skip"
    static let cmdRequestState      = "request_state"

    // ── State sync payload: Phone → Watch ────────────────────
    static let stateSync            = "state_sync"
    static let isRunning            = "isRunning"             // Bool
    static let currentIntervalIndex = "currentIntervalIndex" // Int
    static let intervalEndTime      = "intervalEndTime"      // Double (timeIntervalSince1970)
    static let timeRemaining        = "timeRemaining"       // Double (seconds) — authoritative; used when paused
    static let intervalName         = "intervalName"        // String
    static let intervalDuration     = "intervalDuration"    // Double (seconds)
    static let phase                = "phase"               // WorkoutPhase rawValue String
    static let highIntensityCount   = "hitCount"            // Int
    static let totalIntervals       = "totalIntervals"      // Int
    static let hrLow                = "hrLow"               // Int (BPM) — current phase target floor
    static let hrHigh               = "hrHigh"              // Int (BPM) — current phase target ceiling
    static let workoutComplete      = "workoutComplete"     // Bool
    static let zoneHapticEnabled    = "zoneHapticEnabled"   // Bool — phone-owned setting, mirrored to Watch
    static let intervalHapticsEnabled = "intervalHapticsEnabled" // Bool — phone-owned setting, mirrored to Watch

    // ── Heart rate: Watch → Phone ─────────────────────────────
    static let heartRate            = "hr_update"
    static let hrBPM                = "hrBPM"               // Double
    static let hrTimestamp          = "hrTimestamp"         // Double (timeIntervalSince1970)
}
