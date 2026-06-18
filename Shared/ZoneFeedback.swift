// ZoneFeedback.swift
// Shared between the iOS (N4x4) and watchOS (N4x4Watch) targets.
//
// Pure, device-agnostic logic that decides WHEN to nudge the user back into
// their target heart-rate zone. The same engine runs on both devices so the
// rules can never drift: the Watch drives it for haptics, the phone drives it
// for voice. Each device owns its own output channel; this file owns the
// decision of whether an alert is warranted at all.
//
// Design goals (per product spec):
//   • Heart rate lags effort by 30–60s, so never alert in the first
//     `graceSeconds` of an interval — early readings are meaningless.
//   • A single stray optical-sensor reading must not trigger an alert: the
//     deviation must persist for `sustainedSeconds`.
//   • Never nag: at most one alert per `minAlertInterval` (one per minute).

import Foundation

/// Where the current heart rate sits relative to the active interval's target.
enum HRZoneStatus: Equatable {
    case noTarget   // warmup / cooldown, or no usable range / reading
    case below      // under the target floor
    case inZone
    case above      // over the target ceiling
}

/// The kind of nudge to deliver when the user has drifted out of zone.
enum ZoneAlertKind: Equatable {
    case pushHarder // HR too low during a work interval
    case easeOff    // HR too high during work, or not coming down during recovery
}

/// Tunable timing for the feedback engine. Defaults match the product spec.
struct ZoneFeedbackConfig: Equatable {
    /// Settling window after an interval starts during which no alert fires.
    var graceSeconds: TimeInterval = 60
    /// The deviation must persist this long before an alert fires.
    var sustainedSeconds: TimeInterval = 10
    /// Hard rate limit — never more than one alert within this window.
    var minAlertInterval: TimeInterval = 60

    static let `default` = ZoneFeedbackConfig()
}

/// Stateful evaluator. One instance per output channel (one on the Watch for
/// haptics, one on the phone for voice). Not thread-safe — call from the main
/// queue, which is where both HR delivery paths already dispatch.
final class ZoneFeedbackEngine {

    var config: ZoneFeedbackConfig

    private var outOfZoneSince: Date?
    private var lastAlertAt: Date?
    private var trackedIntervalKey: Int = -1

    init(config: ZoneFeedbackConfig = .default) {
        self.config = config
    }

    /// Pure classification of a reading against a target range. Below/above only
    /// apply to work and recovery phases; warmup/cooldown have no target.
    func status(phase: WorkoutPhase, bpm: Double, low: Int, high: Int) -> HRZoneStatus {
        guard bpm > 0, low > 0, high > 0 else { return .noTarget }
        switch phase {
        case .warmup, .cooldown:
            return .noTarget
        case .highIntensity, .rest:
            if bpm < Double(low)  { return .below }
            if bpm > Double(high) { return .above }
            return .inZone
        }
    }

    /// Returns an alert to deliver right now, or `nil`. Mutates internal timing
    /// state, so call exactly once per incoming HR reading.
    ///
    /// - Parameters:
    ///   - intervalKey: identifies the current interval (e.g. its index). When
    ///     it changes, the sustained-deviation clock resets — but the global
    ///     rate limit deliberately does not, so an interval boundary can't be
    ///     used to bypass the one-per-minute cap.
    ///   - secondsSinceIntervalStart: elapsed time within the current interval.
    func evaluate(intervalKey: Int,
                  phase: WorkoutPhase,
                  bpm: Double,
                  low: Int,
                  high: Int,
                  secondsSinceIntervalStart: TimeInterval,
                  now: Date) -> ZoneAlertKind? {

        if intervalKey != trackedIntervalKey {
            trackedIntervalKey = intervalKey
            outOfZoneSince = nil
        }

        // Map the raw status to an alert direction. Note: being *below* the
        // recovery floor is fine (you're resting well) — only an elevated HR
        // during recovery is worth flagging.
        let pending: ZoneAlertKind?
        switch (phase, status(phase: phase, bpm: bpm, low: low, high: high)) {
        case (.highIntensity, .below): pending = .pushHarder
        case (.highIntensity, .above): pending = .easeOff
        case (.rest,          .above): pending = .easeOff
        default:                       pending = nil
        }

        guard let alert = pending else {
            outOfZoneSince = nil
            return nil
        }

        // Grace window — HR hasn't caught up to effort yet.
        guard secondsSinceIntervalStart >= config.graceSeconds else {
            outOfZoneSince = nil
            return nil
        }

        // Sustained-deviation clock: ignore single stray readings.
        if outOfZoneSince == nil { outOfZoneSince = now }
        guard let since = outOfZoneSince,
              now.timeIntervalSince(since) >= config.sustainedSeconds else {
            return nil
        }

        // Rate limit.
        if let last = lastAlertAt, now.timeIntervalSince(last) < config.minAlertInterval {
            return nil
        }

        lastAlertAt = now
        // Require a fresh sustained window before the next alert.
        outOfZoneSince = nil
        return alert
    }

    /// Clear all state — call when a workout ends or resets.
    func reset() {
        outOfZoneSince = nil
        lastAlertAt = nil
        trackedIntervalKey = -1
    }
}
