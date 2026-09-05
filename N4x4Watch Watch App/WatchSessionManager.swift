// WatchSessionManager.swift
// watchOS side of WatchConnectivity, plus the standalone-workout controller.
//
// Two modes, one rendering state (`timerState`):
//   • mirror — the phone leads. Each state message is stored as the last
//     known phone state and *projected* forward every tick with the synced
//     plan, so the Watch keeps advancing through intervals (display, haptics,
//     zone targets) even when the phone is out of range. The next message
//     re-seeds it. Controls are live only while the phone is reachable; they
//     are never queued (a pause landing ten minutes late is a hazard).
//   • local — the phone was unreachable when the user pressed START, so the
//     Watch runs `WatchWorkoutEngine` itself, records HR, persists its state
//     (relaunch-safe), and on completion queues a `CompletedWatchWorkout` for
//     the phone via transferUserInfo (guaranteed, ordered). The record stays
//     in the pending queue until the phone acks it; the phone dedups by id.

import WatchConnectivity
import Foundation
import WatchKit
import Combine   // @Published / ObservableObject — not transitively available on watchOS

// MARK: - WatchTimerState

struct WatchTimerState: Equatable {
    var isRunning: Bool
    var intervalEndTime: Date
    var reportedTimeRemaining: Double
    var intervalName: String
    var intervalDuration: Double
    var phase: WorkoutPhase
    var highIntensityCount: Int
    var totalIntervals: Int
    var hrLow: Int
    var hrHigh: Int
    var workoutComplete: Bool
    var sessionStarted: Bool
    var currentIntervalIndex: Int
    var zoneHapticEnabled: Bool
    var intervalHapticsEnabled: Bool
    /// Current week streak — drives the Home header, like the phone.
    var streak: Int
    /// The full interval plan (phase + seconds per interval, in order) so the
    /// Watch can draw the phone's timeline bar and project the timeline.
    var planPhases: [WorkoutPhase]
    var planDurations: [Double]
    /// Per-phase targets (0 = none) so projection can re-target each interval.
    var workLow: Int
    var workHigh: Int
    var recoveryLow: Int
    var recoveryHigh: Int
    var workoutTypeRaw: String?

    /// While running, derive the countdown live from the absolute end-time so no
    /// per-second messages are needed. While paused, the end-time is a stale
    /// future date, so use the phone's last reported value — otherwise the Watch
    /// would keep counting down past a pause.
    var timeRemaining: TimeInterval {
        guard isRunning else { return max(0, reportedTimeRemaining) }
        return max(0, intervalEndTime.timeIntervalSinceNow)
    }

    var progressValue: CGFloat {
        guard intervalDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, timeRemaining / intervalDuration)))
    }

    /// Countdown as of a specific instant — used by the TimelineView so the ring
    /// and clock recompute against each 1 s tick without drift.
    func timeRemaining(asOf now: Date) -> TimeInterval {
        guard isRunning else { return max(0, reportedTimeRemaining) }
        return max(0, intervalEndTime.timeIntervalSince(now))
    }

    func progressValue(asOf now: Date) -> CGFloat {
        guard intervalDuration > 0 else { return 0 }
        return CGFloat(min(1, max(0, timeRemaining(asOf: now) / intervalDuration)))
    }

    /// Elapsed time within the current interval — feeds the zone-feedback grace window.
    var secondsSinceIntervalStart: TimeInterval {
        max(0, intervalDuration - timeRemaining)
    }

    /// Whole-plan length in seconds (0 until the plan has synced).
    var planTotal: TimeInterval { planDurations.reduce(0, +) }

    var hasPlan: Bool { planDurations.count > 1 && planPhases.count == planDurations.count }

    /// Seconds into the whole plan as of `now`, walking completed intervals
    /// plus the elapsed part of the current one. Clamped to the plan length.
    func planElapsed(asOf now: Date) -> TimeInterval {
        guard planDurations.indices.contains(currentIntervalIndex) else { return 0 }
        let before = planDurations.prefix(currentIntervalIndex).reduce(0, +)
        let current = planDurations[currentIntervalIndex] - timeRemaining(asOf: now)
        return min(planTotal, before + max(0, current))
    }

    /// The synced plan as an engine plan (nil until the phone has sent one).
    var plan: WatchWorkoutPlan? {
        guard hasPlan else { return nil }
        return WatchWorkoutPlan(
            steps: zip(planPhases, planDurations).map { .init(phase: $0, duration: $1) },
            totalIntervals: totalIntervals,
            workLow: workLow, workHigh: workHigh,
            recoveryLow: recoveryLow, recoveryHigh: recoveryHigh,
            zoneHapticEnabled: zoneHapticEnabled,
            intervalHapticsEnabled: intervalHapticsEnabled,
            workoutTypeRaw: workoutTypeRaw
        )
    }

    /// Phone-led timeline extrapolated to `now`. Between state messages, or
    /// with the phone out of range, the Watch advances through the plan on
    /// its own so the display, haptics and zone targets keep moving. Pauses,
    /// skips and resets still come from the phone and re-seed this.
    func projected(at now: Date) -> WatchTimerState {
        guard isRunning, sessionStarted, !workoutComplete, let plan,
              plan.steps.indices.contains(currentIntervalIndex) else { return self }
        var next = self
        guard let pos = plan.position(index: currentIntervalIndex, endTime: intervalEndTime, at: now) else {
            next.isRunning = false
            next.workoutComplete = true
            next.reportedTimeRemaining = 0
            return next
        }
        guard pos.crossed > 0 else { return self }
        let step = plan.steps[pos.index]
        let range = plan.targetRange(for: step.phase)
        next.currentIntervalIndex = pos.index
        next.intervalEndTime = pos.endTime
        next.intervalDuration = step.duration
        next.phase = step.phase
        next.highIntensityCount = plan.highIntensityCount(through: pos.index)
        next.hrLow = range.low
        next.hrHigh = range.high
        return next
    }

    static let idle = WatchTimerState(
        isRunning: false,
        intervalEndTime: Date(),
        reportedTimeRemaining: 0,
        intervalName: "Ready",
        intervalDuration: 0,
        phase: .warmup,
        highIntensityCount: 0,
        totalIntervals: 4,
        hrLow: 0,
        hrHigh: 0,
        workoutComplete: false,
        sessionStarted: false,
        currentIntervalIndex: 0,
        zoneHapticEnabled: true,
        intervalHapticsEnabled: true,
        streak: 0,
        planPhases: [],
        planDurations: [],
        workLow: 0,
        workHigh: 0,
        recoveryLow: 0,
        recoveryHigh: 0,
        workoutTypeRaw: nil
    )

    /// Idle Home state carrying a cached plan (so the plan bar shows offline).
    static func idle(with plan: WatchWorkoutPlan?, streak: Int) -> WatchTimerState {
        var s = WatchTimerState.idle
        s.streak = streak
        guard let plan else { return s }
        s.planPhases = plan.phases
        s.planDurations = plan.durations
        s.totalIntervals = plan.totalIntervals
        s.workLow = plan.workLow; s.workHigh = plan.workHigh
        s.recoveryLow = plan.recoveryLow; s.recoveryHigh = plan.recoveryHigh
        s.zoneHapticEnabled = plan.zoneHapticEnabled
        s.intervalHapticsEnabled = plan.intervalHapticsEnabled
        s.workoutTypeRaw = plan.workoutTypeRaw
        return s
    }
}

extension WatchWorkoutEngine {
    /// Rendering state for a Watch-led workout — same shape the phone sends,
    /// so every screen works unchanged in either mode.
    func watchState(streak: Int, now: Date) -> WatchTimerState {
        var s = WatchTimerState.idle(with: plan, streak: streak)
        s.isRunning = isRunning
        s.intervalEndTime = intervalEndTime
        s.reportedTimeRemaining = timeRemaining(asOf: now)
        s.intervalName = phase.rawValue
        s.intervalDuration = intervalDuration
        s.phase = phase
        s.highIntensityCount = highIntensityCount
        s.hrLow = targetRange.low
        s.hrHigh = targetRange.high
        s.workoutComplete = isComplete
        s.sessionStarted = true
        s.currentIntervalIndex = currentIndex
        return s
    }
}

enum WatchWorkoutMode: Equatable {
    /// Phone leads; the Watch mirrors and projects.
    case mirror
    /// The Watch leads (started with the phone out of reach).
    case local
}

// MARK: - WatchSessionManager

final class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {

    /// What the screens render, in either mode.
    @Published private(set) var timerState: WatchTimerState = .idle
    @Published private(set) var mode: WatchWorkoutMode = .mirror
    /// Live WCSession reachability. From the Watch this means the paired
    /// iPhone is in range (the iOS app is woken on demand).
    @Published private(set) var isReachable: Bool = false
    /// True once any state payload has arrived (streak is meaningful).
    @Published private(set) var hasReceivedState: Bool = false
    /// Watch-run workouts waiting for the phone to ack them.
    @Published private(set) var pendingWorkouts: [CompletedWatchWorkout] = []
    /// Most recent record the phone confirmed it logged.
    @Published private(set) var lastAckedWorkoutID: UUID?

    /// Authoritative in `.local` mode; nil otherwise.
    private(set) var engine: WatchWorkoutEngine?
    /// Last state the phone sent (mirror mode seed).
    private var lastPhoneState: WatchTimerState = .idle
    /// Plan from the last sync — what a standalone run uses.
    private(set) var cachedPlan: WatchWorkoutPlan?
    /// Set when the user ends a mirrored workout while the phone is
    /// unreachable: hides the stale projection until the next phone message.
    private var mirrorDismissed = false
    private var tickTimer: Timer?
    private var lastEnginePersist = Date.distantPast

    /// Drives haptic nudges when the wearer drifts out of zone.
    private let zoneEngine = ZoneFeedbackEngine()

    private enum Keys {
        static let engine  = "watchLocalEngine"
        static let pending = "watchPendingWorkouts"
        static let plan    = "watchCachedPlan"
    }

    /// The Watch can always start something: with the phone in reach the
    /// phone leads, otherwise the Watch runs the synced (or default) plan.
    var canStart: Bool { true }
    /// Pause/skip/end apply immediately: always on a Watch-led workout, and
    /// on a phone-led one only while the phone is reachable.
    var canControl: Bool { mode == .local || isReachable }
    /// Phone-led workout being shown while the phone is out of range.
    var isProjectingOffline: Bool {
        mode == .mirror && !isReachable && timerState.sessionStarted && !timerState.workoutComplete
    }

    override init() {
        super.init()
        restore()
    }

    // MARK: - Activation

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Foreground return: fresh phone state, catch the engine up, retry syncs.
    func appDidBecomeActive() {
        tick()
        requestStateFromPhone()
        flushPendingWorkouts()
    }

    // MARK: - Commands (mode-aware)

    /// Home START. Phone in reach → the phone leads. Otherwise run here.
    func startWorkout(now: Date = Date()) {
        if mode == .mirror, isReachable {
            sendCommand(WatchMessageKey.cmdStartPause)
        } else {
            startLocalWorkout(now: now)
        }
    }

    func startLocalWorkout(now: Date = Date()) {
        guard engine == nil || engine?.isComplete == true else { return }
        let plan = cachedPlan ?? .fallback
        guard let started = WatchWorkoutEngine.start(plan: plan, now: now) else { return }
        engine = started
        mode = .local
        zoneEngine.reset()
        persistEngine(force: true)
        tick(now: now)
    }

    func togglePause(now: Date = Date()) {
        switch mode {
        case .local:
            engine?.togglePause(now: now)
            persistEngine(force: true)
            tick(now: now)
        case .mirror:
            guard isReachable else { return }
            sendCommand(WatchMessageKey.cmdStartPause)
        }
    }

    func skip(now: Date = Date()) {
        switch mode {
        case .local:
            engine?.skip(now: now)
            persistEngine(force: true)
            tick(now: now)
        case .mirror:
            guard isReachable else { return }
            sendCommand(WatchMessageKey.cmdSkip)
        }
    }

    /// END mid-workout. Watch-led: abandon (nothing is logged). Phone-led and
    /// reachable: the phone resets. Phone-led and out of range: stop showing
    /// it here — the phone carries on and logs it.
    func endWorkout() {
        switch mode {
        case .local:
            clearLocalWorkout()
        case .mirror:
            if isReachable {
                sendCommand(WatchMessageKey.cmdReset)
            } else {
                mirrorDismissed = true
                tick()
            }
        }
    }

    /// Complete screen "Done" on a Watch-led workout: back to Home; the
    /// record keeps syncing in the background.
    func dismissCompletedLocalWorkout() {
        guard mode == .local, engine?.isComplete == true else { return }
        clearLocalWorkout()
        flushPendingWorkouts()
    }

    /// Complete screen "Discard" on a Watch-led workout: drop the record and
    /// tell the phone, in case a copy already got through.
    func discardCompletedLocalWorkout() {
        guard mode == .local, let engine else { return }
        let id = engine.id
        pendingWorkouts.removeAll { $0.id == id }
        persistPending()
        if WCSession.isSupported(), WCSession.default.activationState == .activated {
            for transfer in WCSession.default.outstandingUserInfoTransfers
            where (transfer.userInfo[WatchMessageKey.workoutID] as? String) == id.uuidString {
                transfer.cancel()
            }
            WCSession.default.transferUserInfo([
                WatchMessageKey.messageType: WatchMessageKey.workoutDiscard,
                WatchMessageKey.workoutID:   id.uuidString,
            ])
        }
        clearLocalWorkout()
    }

    /// Discard from the phone-led Complete screen (phone must be reachable).
    func discardPhoneWorkout() {
        guard mode == .mirror, isReachable else { return }
        sendCommand(WatchMessageKey.cmdReset)
    }

    private func clearLocalWorkout() {
        engine = nil
        mode = .mirror
        UserDefaults.standard.removeObject(forKey: Keys.engine)
        zoneEngine.reset()
        tick()
    }

    func requestStateFromPhone() {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            [WatchMessageKey.messageType: WatchMessageKey.cmdRequestState],
            replyHandler: nil,
            errorHandler: nil
        )
    }

    /// Live-only. Deliberately no queued fallback: a control that lands
    /// minutes later, when the phone comes back, would be a nasty surprise.
    private func sendCommand(_ type: String) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([WatchMessageKey.messageType: type],
                                      replyHandler: nil, errorHandler: nil)
    }

    // MARK: - Tick (projection / engine reconcile)

    /// Recomputes the rendering state. Publishes only on change so views
    /// aren't invalidated every second (the countdown itself is derived by
    /// the views from the absolute end time).
    func tick(now: Date = Date()) {
        let next: WatchTimerState
        switch mode {
        case .local:
            guard var e = engine else { next = idleState(); break }
            let previousIndex = e.currentIndex
            e.reconcile(now: now)
            if e != engine {
                engine = e
                // Boundaries and completion are written through immediately;
                // anything else rides the 30 s HR-sample throttle.
                persistEngine(force: e.isComplete || e.currentIndex != previousIndex)
            }
            if e.isComplete, let record = e.completedRecord(),
               !pendingWorkouts.contains(where: { $0.id == record.id }),
               lastAckedWorkoutID != record.id {
                pendingWorkouts.append(record)
                persistPending()
                persistEngine(force: true)
                flushPendingWorkouts()
            }
            next = e.watchState(streak: lastPhoneState.streak, now: now)
        case .mirror:
            if mirrorDismissed {
                next = idleState()
            } else {
                next = lastPhoneState.projected(at: now)
            }
        }
        publish(next)
        updateTimer()
    }

    private func idleState() -> WatchTimerState {
        .idle(with: cachedPlan, streak: lastPhoneState.streak)
    }

    private func publish(_ next: WatchTimerState) {
        guard next != timerState else { return }
        // Clear any lingering zone-alert state when the workout stops/resets.
        if timerState.isRunning, !next.isRunning { zoneEngine.reset() }
        timerState = next
    }

    private func updateTimer() {
        let active = timerState.sessionStarted && !timerState.workoutComplete
        if active, tickTimer == nil {
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.tick() }
            t.tolerance = 0.2
            RunLoop.main.add(t, forMode: .common)
            tickTimer = t
        } else if !active, let t = tickTimer {
            t.invalidate()
            tickTimer = nil
        }
    }

    // MARK: - Zone feedback (haptics) + HR recording

    /// Called with each fresh HR reading. Fires a distinct wrist haptic when the
    /// wearer has been sustainedly out of zone, subject to the grace window and
    /// the one-per-minute rate limit enforced by the shared engine.
    func evaluateZoneHaptic(bpm: Double) {
        let s = timerState
        guard s.isRunning, s.zoneHapticEnabled, bpm > 0 else { return }

        let alert = zoneEngine.evaluate(
            intervalKey: s.currentIntervalIndex,
            phase: s.phase,
            bpm: bpm,
            low: s.hrLow,
            high: s.hrHigh,
            secondsSinceIntervalStart: s.secondsSinceIntervalStart,
            now: Date()
        )

        guard let alert else { return }
        // .directionUp = "push" (HR too low); .directionDown = "ease off" (HR too high).
        let haptic: WKHapticType = (alert == .pushHarder) ? .directionUp : .directionDown
        WKInterfaceDevice.current().play(haptic)
    }

    /// Watch-led workouts keep their own HR series for the phone's charts.
    func recordHeartRate(_ bpm: Double, now: Date = Date()) {
        guard mode == .local, var e = engine else { return }
        e.record(bpm: bpm, now: now)
        guard e != engine else { return }
        engine = e
        persistEngine(force: false)
    }

    /// Current zone classification for colour-coding the HR display.
    func zoneStatus(bpm: Double) -> HRZoneStatus {
        zoneEngine.status(phase: timerState.phase, bpm: bpm,
                          low: timerState.hrLow, high: timerState.hrHigh)
    }

    // MARK: - Pending workout sync

    /// Queue every un-acked record that isn't already in flight. Called after
    /// completion, on activation, on reachability change and on foreground.
    func flushPendingWorkouts() {
        guard !pendingWorkouts.isEmpty, WCSession.isSupported(),
              WCSession.default.activationState == .activated else { return }
        let inFlight = Set(WCSession.default.outstandingUserInfoTransfers
            .compactMap { $0.userInfo[WatchMessageKey.workoutID] as? String })
        for record in pendingWorkouts where !inFlight.contains(record.id.uuidString) {
            guard let data = record.encoded() else { continue }
            WCSession.default.transferUserInfo([
                WatchMessageKey.messageType:  WatchMessageKey.workoutCompleted,
                WatchMessageKey.workoutID:    record.id.uuidString,
                WatchMessageKey.workoutRecord: data,
            ])
        }
    }

    private func handleAck(_ p: [String: Any]) {
        guard let idString = p[WatchMessageKey.workoutID] as? String,
              let id = UUID(uuidString: idString) else { return }
        pendingWorkouts.removeAll { $0.id == id }
        lastAckedWorkoutID = id
        persistPending()
    }

    // MARK: - Persistence

    private func restore() {
        let d = UserDefaults.standard
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        if let data = d.data(forKey: Keys.plan),
           let plan = try? decoder.decode(WatchWorkoutPlan.self, from: data) {
            cachedPlan = plan
        }
        if let data = d.data(forKey: Keys.pending),
           let pending = try? decoder.decode([CompletedWatchWorkout].self, from: data) {
            pendingWorkouts = pending
        }
        if let data = d.data(forKey: Keys.engine),
           let saved = try? decoder.decode(WatchWorkoutEngine.self, from: data) {
            // A Watch-led workout survived a relaunch (or crash) — pick it
            // back up. Completed-but-not-dismissed shows the Complete screen.
            engine = saved
            mode = .local
        }
        tick()
    }

    private func persistEngine(force: Bool) {
        let now = Date()
        // HR samples arrive ~1/s; write them through at most every 30 s.
        guard force || now.timeIntervalSince(lastEnginePersist) > 30 else { return }
        lastEnginePersist = now
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let engine, let data = try? encoder.encode(engine) {
            UserDefaults.standard.set(data, forKey: Keys.engine)
        } else {
            UserDefaults.standard.removeObject(forKey: Keys.engine)
        }
    }

    private func persistPending() {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(pendingWorkouts) {
            UserDefaults.standard.set(data, forKey: Keys.pending)
        }
    }

    private func cachePlan(from state: WatchTimerState) {
        guard let plan = state.plan, plan != cachedPlan else { return }
        cachedPlan = plan
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(plan) {
            UserDefaults.standard.set(data, forKey: Keys.plan)
        }
    }

    // MARK: - Demo (DEBUG screenshots)

    #if DEBUG
    /// Seeds a phone-led state without a phone, for layout checks.
    func injectDemo(phoneState: WatchTimerState, reachable: Bool) {
        lastPhoneState = phoneState
        hasReceivedState = true
        isReachable = reachable
        cachePlan(from: phoneState)
        mode = .mirror
        engine = nil
        UserDefaults.standard.removeObject(forKey: Keys.engine)
        pendingWorkouts = []
        persistPending()
        tick()
    }
    #endif

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
            // Ask for fresh state as soon as the channel is up so the Home
            // screen (streak, plan) isn't stale from the last app context.
            self?.requestStateFromPhone()
            self?.flushPendingWorkouts()
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in
            self?.isReachable = session.isReachable
            if session.isReachable {
                self?.requestStateFromPhone()
                self?.flushPendingWorkouts()
            }
        }
    }

    /// Real-time message (phone reachable).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.route(message) }
    }

    /// Stored context — delivered when the Watch wasn't reachable at send time.
    func session(_ session: WCSession,
                 didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.route(applicationContext) }
    }

    /// Background user-info delivery (state fallback and workout acks).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.route(userInfo) }
    }

    private func route(_ p: [String: Any]) {
        switch p[WatchMessageKey.messageType] as? String {
        case WatchMessageKey.stateSync:  applyStatePayload(p)
        case WatchMessageKey.workoutAck: handleAck(p)
        default: break
        }
    }

    // MARK: - State parsing

    private func applyStatePayload(_ p: [String: Any]) {
        let state = WatchTimerState(
            isRunning:            p[WatchMessageKey.isRunning]            as? Bool   ?? false,
            intervalEndTime:      Date(timeIntervalSince1970:
                                    p[WatchMessageKey.intervalEndTime]    as? Double ?? 0),
            reportedTimeRemaining: p[WatchMessageKey.timeRemaining]       as? Double ?? 0,
            intervalName:         p[WatchMessageKey.intervalName]         as? String ?? "",
            intervalDuration:     p[WatchMessageKey.intervalDuration]     as? Double ?? 0,
            phase:                WorkoutPhase(rawValue:
                                    p[WatchMessageKey.phase]              as? String ?? "")
                                    ?? .warmup,
            highIntensityCount:   p[WatchMessageKey.highIntensityCount]   as? Int    ?? 0,
            totalIntervals:       p[WatchMessageKey.totalIntervals]       as? Int    ?? 4,
            hrLow:                p[WatchMessageKey.hrLow]                as? Int    ?? 0,
            hrHigh:               p[WatchMessageKey.hrHigh]               as? Int    ?? 0,
            workoutComplete:      p[WatchMessageKey.workoutComplete]      as? Bool   ?? false,
            sessionStarted:       p[WatchMessageKey.sessionStarted]       as? Bool   ?? false,
            currentIntervalIndex: p[WatchMessageKey.currentIntervalIndex] as? Int    ?? 0,
            zoneHapticEnabled:    p[WatchMessageKey.zoneHapticEnabled]    as? Bool   ?? true,
            intervalHapticsEnabled: p[WatchMessageKey.intervalHapticsEnabled] as? Bool ?? true,
            streak:               p[WatchMessageKey.streak]               as? Int    ?? 0,
            // Keep the two plan arrays parallel: an unknown phase maps to
            // warm-up rather than being dropped, so durations stay aligned.
            planPhases:           ((p[WatchMessageKey.planPhases] as? [String]) ?? [])
                                    .map { WorkoutPhase(rawValue: $0) ?? .warmup },
            planDurations:        p[WatchMessageKey.planDurations]        as? [Double] ?? [],
            workLow:              p[WatchMessageKey.workHRLow]            as? Int    ?? 0,
            workHigh:             p[WatchMessageKey.workHRHigh]           as? Int    ?? 0,
            recoveryLow:          p[WatchMessageKey.recoveryHRLow]        as? Int    ?? 0,
            recoveryHigh:         p[WatchMessageKey.recoveryHRHigh]       as? Int    ?? 0,
            workoutTypeRaw:       p[WatchMessageKey.workoutTypeRaw]       as? String
        )
        lastPhoneState = state
        hasReceivedState = true
        cachePlan(from: state)
        // A fresh phone message always supersedes a locally dismissed projection.
        mirrorDismissed = false
        // A Watch-led workout in progress is not interrupted by phone state;
        // it's applied once the user finishes here.
        guard mode == .mirror else { return }
        tick()
    }
}
