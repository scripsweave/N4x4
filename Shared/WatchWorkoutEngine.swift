// WatchWorkoutEngine.swift
// Shared between the iOS (N4x4) and watchOS (N4x4Watch) targets.
//
// The standalone Watch workout: a pure-Foundation interval engine and the
// record it hands the phone to log. No UI, HealthKit or WatchConnectivity
// here, so it compiles into both targets and is unit-tested from N4x4Tests.
//
// Who leads a workout:
//   • Phone reachable at start → the phone's TimerViewModel leads (voice,
//     Live Activity, Bluetooth HR). The Watch mirrors, and between state
//     messages — or with the phone out of range — it *projects* the phone's
//     timeline forward with `WatchWorkoutPlan.position`, so the display,
//     haptics and zone targets keep moving.
//   • Phone unreachable at start → the Watch runs this engine as the source
//     of truth, records heart rate, and on completion queues a
//     `CompletedWatchWorkout` for the phone (guaranteed WCSession delivery,
//     idempotent on the phone), which logs it like any other session.
//
// The engine is absolute-time based: while running, `intervalEndTime` is the
// anchor and `reconcile(now:)` walks through every boundary that has passed,
// so a suspended or relaunched app catches up without losing intervals.

import Foundation

// MARK: - Plan

struct WatchWorkoutPlan: Codable, Equatable {
    struct Step: Codable, Equatable {
        let phase: WorkoutPhase
        let duration: TimeInterval
    }

    var steps: [Step]
    /// Number of work intervals (for "ROUND n OF total").
    var totalIntervals: Int
    /// Target zones per phase; 0 = no target (the Watch has no max-HR of its own).
    var workLow: Int
    var workHigh: Int
    var recoveryLow: Int
    var recoveryHigh: Int
    /// Phone-owned settings mirrored into the plan so standalone runs honour them.
    var zoneHapticEnabled: Bool
    var intervalHapticsEnabled: Bool
    /// The phone's default workout type (`WorkoutType.rawValue`) for logging.
    var workoutTypeRaw: String?

    var totalDuration: TimeInterval { steps.reduce(0) { $0 + $1.duration } }
    var phases: [WorkoutPhase] { steps.map(\.phase) }
    var durations: [Double] { steps.map(\.duration) }

    func targetRange(for phase: WorkoutPhase) -> (low: Int, high: Int) {
        switch phase {
        case .highIntensity: return (workLow, workHigh)
        case .rest:          return (recoveryLow, recoveryHigh)
        case .warmup, .cooldown: return (0, 0)
        }
    }

    /// Work-interval number at `index` (how many work steps up to and including it).
    func highIntensityCount(through index: Int) -> Int {
        guard index >= 0 else { return 0 }
        return steps.prefix(min(steps.count, index + 1)).filter { $0.phase == .highIntensity }.count
    }

    /// Walks the timeline forward from a known position: given that step
    /// `index` ends at `endTime`, which step is current at `now` and when does
    /// it end? `crossed` counts the boundaries passed. Returns nil once the
    /// plan has run out — the workout is complete.
    func position(index: Int, endTime: Date, at now: Date)
        -> (index: Int, endTime: Date, crossed: Int)? {
        guard steps.indices.contains(index) else { return nil }
        var i = index, end = endTime, crossed = 0
        while now >= end {
            i += 1
            crossed += 1
            guard steps.indices.contains(i) else { return nil }
            end = end.addingTimeInterval(steps[i].duration)
        }
        return (i, end, crossed)
    }

    /// The protocol as shipped, used when the Watch has never synced a plan:
    /// 5 min warm-up, 4 × (4 min work / 3 min recovery), 5 min cool-down
    /// (matches `TimerViewModel.resetSettingsToDefaults`). No HR targets.
    static let fallback: WatchWorkoutPlan = {
        var steps = [Step(phase: .warmup, duration: 5 * 60)]
        for i in 1...4 {
            steps.append(Step(phase: .highIntensity, duration: 4 * 60))
            if i < 4 { steps.append(Step(phase: .rest, duration: 3 * 60)) }
        }
        steps.append(Step(phase: .cooldown, duration: 5 * 60))
        return WatchWorkoutPlan(steps: steps, totalIntervals: 4,
                                workLow: 0, workHigh: 0, recoveryLow: 0, recoveryHigh: 0,
                                zoneHapticEnabled: true, intervalHapticsEnabled: true,
                                workoutTypeRaw: nil)
    }()
}

extension WorkoutPhase {
    /// Span kind used by the phone's `HeartRateSeries.IntervalSpan`.
    var seriesKind: String {
        switch self {
        case .warmup:        return "warmup"
        case .highIntensity: return "work"
        case .rest:          return "recovery"
        case .cooldown:      return "cooldown"
        }
    }
}

// MARK: - Completed record (wire format Watch → Phone)

struct CompletedWatchWorkout: Codable, Equatable, Identifiable {
    struct Sample: Codable, Equatable {
        let t: Double      // seconds since start (wall clock; pauses are gaps)
        let bpm: Double
    }
    struct Span: Codable, Equatable {
        let kind: String
        let workNumber: Int
        let start: Double
        let end: Double
        let targetLo: Int
        let targetHi: Int
    }

    let id: UUID
    let startedAt: Date
    let completedAt: Date
    let workoutTypeRaw: String?
    let warmupSeconds: TimeInterval
    let highIntensitySeconds: TimeInterval
    let recoverySeconds: TimeInterval
    let cooldownSeconds: TimeInterval
    let cooldownSkipped: Bool
    let samples: [Sample]
    let spans: [Span]

    var totalSeconds: TimeInterval {
        warmupSeconds + highIntensitySeconds + recoverySeconds + cooldownSeconds
    }
    var averageBPM: Int? {
        guard !samples.isEmpty else { return nil }
        return Int((samples.map(\.bpm).reduce(0, +) / Double(samples.count)).rounded())
    }
    var maxBPM: Int? { samples.map(\.bpm).max().map { Int($0.rounded()) } }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }
    private static var decoder: JSONDecoder {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }

    func encoded() -> Data? { try? Self.encoder.encode(self) }
    static func decode(_ data: Data) -> CompletedWatchWorkout? {
        try? decoder.decode(CompletedWatchWorkout.self, from: data)
    }
}

// MARK: - Engine

struct WatchWorkoutEngine: Codable, Equatable {
    let id: UUID
    let plan: WatchWorkoutPlan
    let startDate: Date

    private(set) var currentIndex: Int
    private(set) var isRunning: Bool
    /// Absolute end of the current step — meaningful while running.
    private(set) var intervalEndTime: Date
    /// Countdown frozen at the last pause — meaningful while paused.
    private(set) var pausedRemaining: TimeInterval
    private(set) var isComplete: Bool
    private(set) var completionDate: Date?
    private(set) var cooldownSkipped: Bool
    /// Wall-clock start of the running stretch of the current step; nil while paused.
    private var segmentStart: Date?
    /// Time actually spent per phase (pauses excluded), keyed by phase rawValue.
    private(set) var elapsedByPhase: [String: TimeInterval]
    private(set) var samples: [CompletedWatchWorkout.Sample]
    private(set) var spans: [CompletedWatchWorkout.Span]
    private var openSpanStart: TimeInterval

    /// Kept sample cadence, matching the phone's recorder (one per 2 s).
    static let sampleBucketSeconds: Double = 2

    static func start(plan: WatchWorkoutPlan, now: Date = Date(), id: UUID = UUID()) -> WatchWorkoutEngine? {
        guard let first = plan.steps.first else { return nil }
        return WatchWorkoutEngine(
            id: id, plan: plan, startDate: now,
            currentIndex: 0, isRunning: true,
            intervalEndTime: now.addingTimeInterval(first.duration),
            pausedRemaining: first.duration,
            isComplete: false, completionDate: nil, cooldownSkipped: false,
            segmentStart: now, elapsedByPhase: [:], samples: [], spans: [],
            openSpanStart: 0
        )
    }

    // MARK: Derived

    var currentStep: WatchWorkoutPlan.Step {
        plan.steps[min(max(0, currentIndex), plan.steps.count - 1)]
    }
    var phase: WorkoutPhase { currentStep.phase }
    var intervalDuration: TimeInterval { currentStep.duration }
    var highIntensityCount: Int { plan.highIntensityCount(through: currentIndex) }
    var targetRange: (low: Int, high: Int) { plan.targetRange(for: phase) }

    func timeRemaining(asOf now: Date) -> TimeInterval {
        if isComplete { return 0 }
        return isRunning ? max(0, intervalEndTime.timeIntervalSince(now)) : max(0, pausedRemaining)
    }

    func elapsed(for phase: WorkoutPhase) -> TimeInterval {
        elapsedByPhase[phase.rawValue] ?? 0
    }

    // MARK: Commands

    /// Advances through every boundary that has passed by `now`. Returns the
    /// number of boundaries crossed (0 when nothing changed). Safe to call
    /// from any tick, foreground return, or relaunch.
    @discardableResult
    mutating func reconcile(now: Date) -> Int {
        guard isRunning, !isComplete else { return 0 }
        var crossed = 0
        while now >= intervalEndTime, !isComplete {
            advance(at: intervalEndTime)
            crossed += 1
        }
        return crossed
    }

    mutating func pause(now: Date) {
        reconcile(now: now)
        guard isRunning, !isComplete else { return }
        pausedRemaining = max(0, intervalEndTime.timeIntervalSince(now))
        closeSegment(at: now)
        isRunning = false
    }

    mutating func resume(now: Date) {
        guard !isRunning, !isComplete else { return }
        intervalEndTime = now.addingTimeInterval(pausedRemaining)
        segmentStart = now
        isRunning = true
    }

    mutating func togglePause(now: Date) {
        if isRunning { pause(now: now) } else { resume(now: now) }
    }

    /// Ends the current step now. Skipping the cool-down completes the workout
    /// and is flagged in the record, as on the phone. Works while paused too
    /// (the paused countdown becomes the next step's full length).
    mutating func skip(now: Date) {
        reconcile(now: now)
        guard !isComplete else { return }
        if phase == .cooldown { cooldownSkipped = true }
        advance(at: now)
    }

    /// Records a heart-rate reading. Ignored while paused (charts show the
    /// gap) and thinned to one sample per bucket, like the phone's recorder.
    mutating func record(bpm: Double, now: Date) {
        guard isRunning, !isComplete, bpm > 0 else { return }
        let t = now.timeIntervalSince(startDate)
        guard t >= 0 else { return }
        if let last = samples.last, t - last.t < Self.sampleBucketSeconds { return }
        samples.append(.init(t: t, bpm: bpm))
    }

    /// The record for the phone, once complete.
    func completedRecord() -> CompletedWatchWorkout? {
        guard isComplete, let completionDate else { return nil }
        return CompletedWatchWorkout(
            id: id, startedAt: startDate, completedAt: completionDate,
            workoutTypeRaw: plan.workoutTypeRaw,
            warmupSeconds: elapsed(for: .warmup),
            highIntensitySeconds: elapsed(for: .highIntensity),
            recoverySeconds: elapsed(for: .rest),
            cooldownSeconds: elapsed(for: .cooldown),
            cooldownSkipped: cooldownSkipped,
            samples: samples, spans: spans
        )
    }

    // MARK: Internals

    private mutating func advance(at time: Date) {
        closeSegment(at: time)
        closeSpan(at: time)
        let next = currentIndex + 1
        guard next < plan.steps.count else {
            isRunning = false
            isComplete = true
            completionDate = time
            segmentStart = nil
            return
        }
        currentIndex = next
        if isRunning {
            intervalEndTime = time.addingTimeInterval(plan.steps[next].duration)
            segmentStart = time
        } else {
            pausedRemaining = plan.steps[next].duration
        }
        openSpanStart = max(0, time.timeIntervalSince(startDate))
    }

    private mutating func closeSegment(at time: Date) {
        guard let start = segmentStart else { return }
        elapsedByPhase[phase.rawValue, default: 0] += max(0, time.timeIntervalSince(start))
        segmentStart = nil
    }

    private mutating func closeSpan(at time: Date) {
        let end = max(openSpanStart, time.timeIntervalSince(startDate))
        // Zero-length spans (double advance in the same instant) add noise, drop them.
        guard end - openSpanStart > 0.5 else { return }
        let range = targetRange
        spans.append(.init(kind: phase.seriesKind,
                           workNumber: phase == .highIntensity ? highIntensityCount : 0,
                           start: openSpanStart, end: end,
                           targetLo: range.low, targetHi: range.high))
    }
}
