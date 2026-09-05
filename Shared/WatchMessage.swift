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
    static let cmdReset             = "cmd_reset"
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
    static let sessionStarted       = "sessionStarted"      // Bool
    static let zoneHapticEnabled    = "zoneHapticEnabled"   // Bool — phone-owned setting, mirrored to Watch
    static let intervalHapticsEnabled = "intervalHapticsEnabled" // Bool — phone-owned setting, mirrored to Watch
    static let streak               = "streak"              // Int — current week streak (Watch Home header)
    static let planPhases           = "planPhases"          // [String] — WorkoutPhase rawValue per interval, in order
    static let planDurations        = "planDurations"       // [Double] — seconds per interval, parallel to planPhases
    static let workHRLow            = "workHRLow"           // Int — work-interval target floor (0 = none)
    static let workHRHigh           = "workHRHigh"          // Int — work-interval target ceiling
    static let recoveryHRLow        = "recoveryHRLow"       // Int — recovery target floor (0 = none)
    static let recoveryHRHigh       = "recoveryHRHigh"      // Int — recovery target ceiling
    static let workoutTypeRaw       = "workoutTypeRaw"      // String — default WorkoutType rawValue, for standalone logs

    // ── Standalone workout sync: Watch → Phone via transferUserInfo (queued,
    //    guaranteed, in order) and the phone's ack back the same way. ──
    static let workoutCompleted     = "workout_completed"   // carries workoutID + workoutRecord
    static let workoutDiscard       = "workout_discard"     // carries workoutID — user discarded on the Watch
    static let workoutAck           = "workout_ack"         // Phone → Watch: carries workoutID
    static let workoutID            = "workoutID"           // String (UUID)
    static let workoutRecord        = "workoutRecord"       // Data (JSON CompletedWatchWorkout)

    // ── Heart rate: Watch → Phone ─────────────────────────────
    static let heartRate            = "hr_update"
    static let hrBPM                = "hrBPM"               // Double
    static let hrTimestamp          = "hrTimestamp"         // Double (timeIntervalSince1970)
}
