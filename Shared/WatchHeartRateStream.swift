// Timestamped, latest-only delivery. Shared so dropped sends and delayed
// callbacks can be tested without HealthKit, WatchConnectivity or a sensor.
import Foundation

struct WatchHeartRateSample: Equatable {
    static let maximumAge: TimeInterval = 10
    let bpm: Double
    let measuredAt: Date
    var workoutID: String? = nil

    func isFresh(at now: Date) -> Bool {
        let age = now.timeIntervalSince(measuredAt)
        return bpm.isFinite && (1...300).contains(bpm)
            && age.isFinite && age >= -2 && age < Self.maximumAge
    }

    var message: [String: Any] {
        var payload: [String: Any] = [WatchMessageKey.messageType: WatchMessageKey.heartRate,
                                     WatchMessageKey.hrBPM: bpm,
                                     WatchMessageKey.hrTimestamp: measuredAt.timeIntervalSince1970]
        if let workoutID { payload[WatchMessageKey.workoutID] = workoutID }
        return payload
    }

    init(bpm: Double, measuredAt: Date, workoutID: String? = nil) {
        self.bpm = bpm
        self.measuredAt = measuredAt
        self.workoutID = workoutID
    }

    init?(message: [String: Any]) {
        guard message[WatchMessageKey.messageType] as? String == WatchMessageKey.heartRate,
              let bpm = message[WatchMessageKey.hrBPM] as? Double,
              let timestamp = message[WatchMessageKey.hrTimestamp] as? Double,
              timestamp.isFinite else { return nil }
        self.init(bpm: bpm, measuredAt: Date(timeIntervalSince1970: timestamp),
                  workoutID: message[WatchMessageKey.workoutID] as? String)
    }
}

/// Live messages, retries and application context can deliver the same sample
/// or arrive out of order. Neither may refresh an old reading's expiry.
struct WatchHeartRateInbox {
    private var lastMeasuredAt: Date?
    private var lastSample: WatchHeartRateSample?

    func hasAccepted(_ sample: WatchHeartRateSample) -> Bool { lastSample == sample }

    mutating func accept(_ message: [String: Any], now: Date) -> WatchHeartRateSample? {
        guard let sample = WatchHeartRateSample(message: message), sample.isFresh(at: now) else { return nil }
        // Recover if the devices' wall clock was moved backwards.
        if let lastMeasuredAt, lastMeasuredAt.timeIntervalSince(now) > 2 {
            self.lastMeasuredAt = nil
        }
        guard lastMeasuredAt.map({ sample.measuredAt > $0 }) ?? true else { return nil }
        lastMeasuredAt = sample.measuredAt
        lastSample = sample
        return sample
    }
}

/// Main-queue, latest-only delivery. One live send at a time; both an error and
/// a missing reply release it. New readings coalesce instead of building a queue.
final class WatchHeartRateDelivery {
    typealias Send = ([String: Any], @escaping (Bool) -> Void) -> Void
    private let now: () -> Date
    private let activated: () -> Bool
    private let reachable: () -> Bool
    private let send: Send
    private let saveContext: ([String: Any]) -> Void
    private let retryLater: (@escaping () -> Void) -> Void
    private let acknowledged: (WatchHeartRateSample) -> Void
    private var latest: WatchHeartRateSample?
    private var inFlight: UUID?
    private var retryToken: UUID?
    private var attempts = 0

    init(now: @escaping () -> Date = Date.init,
         activated: @escaping () -> Bool,
         reachable: @escaping () -> Bool,
         send: @escaping Send,
         saveContext: @escaping ([String: Any]) -> Void,
         retryLater: @escaping (@escaping () -> Void) -> Void,
         acknowledged: @escaping (WatchHeartRateSample) -> Void = { _ in }) {
        self.now = now
        self.activated = activated
        self.reachable = reachable
        self.send = send
        self.saveContext = saveContext
        self.retryLater = retryLater
        self.acknowledged = acknowledged
    }

    func receive(_ sample: WatchHeartRateSample) {
        if let latest, latest.measuredAt.timeIntervalSince(now()) > 2 { reset() }
        guard sample.isFresh(at: now()),
              latest.map({ sample.measuredAt > $0.measuredAt }) ?? true else { return }
        latest = sample
        attempts = 0
        retryToken = nil
        flush()
    }

    func reset() {
        latest = nil
        inFlight = nil
        retryToken = nil
        attempts = 0
    }

    func resendLatest() {
        guard inFlight == nil else { return }
        attempts = 0
        retryToken = nil
        flush()
    }

    private func flush() {
        guard inFlight == nil, activated(), let sample = latest,
              sample.isFresh(at: now()), attempts < 2 else { return }
        attempts += 1
        guard reachable() else {
            saveContext(sample.message)
            scheduleRetry()
            return
        }
        let token = UUID()
        inFlight = token
        send(sample.message) { [weak self] success in
            self?.complete(token: token, sample: sample, success: success)
        }
        // WCSession callbacks may be delayed indefinitely. Bound that wait,
        // and ignore a late reply after a newer attempt has taken over.
        retryLater { [weak self] in self?.complete(token: token, sample: sample, success: false) }
    }

    private func complete(token: UUID, sample: WatchHeartRateSample, success: Bool) {
        guard inFlight == token else { return }
        inFlight = nil
        if success, sample.isFresh(at: now()) { acknowledged(sample) }
        guard let latest, latest.isFresh(at: now()), activated() else { return }
        if !success { saveContext(latest.message) }
        if latest != sample {
            flush()
        } else if !success {
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard attempts < 2 else { return }
        let token = UUID()
        retryToken = token
        retryLater { [weak self] in
            guard let self, self.retryToken == token else { return }
            self.retryToken = nil
            self.flush()
        }
    }
}

/// Startup recovery must complete before starting anything new. A new logical
/// workout must wait for the previous sensor session to end. Tokens reject late
/// callbacks; a failed session is retried only on an explicit foreground refresh.
struct WatchWorkoutSessionLifecycle {
    enum Action: Equatable {
        case start(workoutID: String, token: Int)
        case stop(token: Int)
    }
    private(set) var prepared = false
    private(set) var desiredID: String?
    private var activeID: String?
    private var token = 0
    private var stopping = false
    private var failedID: String?

    mutating func desire(sessionStarted: Bool, complete: Bool, workoutID: String?) -> Action? {
        desiredID = sessionStarted && !complete ? (workoutID ?? "legacy") : nil
        if desiredID != failedID { failedID = nil }
        return reconcile()
    }

    mutating func preparationFinished() -> Action? {
        prepared = true
        return reconcile()
    }

    mutating func ended(token endedToken: Int, failed: Bool = false) -> Action? {
        guard activeID != nil, endedToken == token else { return nil }
        let wasStopping = stopping
        if failed || !wasStopping { failedID = activeID }
        activeID = nil
        stopping = false
        return reconcile()
    }

    mutating func retry() -> Action? {
        failedID = nil
        return reconcile()
    }

    /// Explicit user retry of a session that is running but silent: end it,
    /// then start the same workout again once `.ended` arrives. A deliberate
    /// stop never latches the workout as failed.
    mutating func restart() -> Action? {
        failedID = nil
        guard prepared, let activeID, activeID == desiredID, !stopping else { return reconcile() }
        stopping = true
        return .stop(token: token)
    }

    private mutating func reconcile() -> Action? {
        guard prepared else { return nil }
        if let activeID {
            guard activeID != desiredID, !stopping else { return nil }
            stopping = true
            return .stop(token: token)
        }
        guard let desiredID, desiredID != failedID else { return nil }
        token += 1
        activeID = desiredID
        return .start(workoutID: desiredID, token: token)
    }
}

/// Authorization and abandoned-session cleanup have no guaranteed callback.
/// Without an escape, one missing callback disabled the sensor for the rest of
/// the process with no error and a Retry that did nothing. A stalled attempt
/// may be superseded; its token makes late callbacks harmless. Monotonic clock.
struct WatchSessionPreparation {
    static let stallTimeout: TimeInterval = 15
    private(set) var token = 0
    private var startedAt: TimeInterval?

    var isPreparing: Bool { startedAt != nil }

    /// nil while a recent attempt is still within its timeout.
    mutating func begin(now: TimeInterval) -> Int? {
        if let startedAt, now >= startedAt, now - startedAt < Self.stallTimeout { return nil }
        token += 1
        startedAt = now
        return token
    }

    func isStalled(token: Int, now: TimeInterval) -> Bool {
        guard token == self.token, let startedAt else { return false }
        return now < startedAt || now - startedAt >= Self.stallTimeout
    }

    /// True only for the current attempt; a superseded attempt's callback is ignored.
    mutating func end(token: Int) -> Bool {
        guard token == self.token, startedAt != nil else { return false }
        startedAt = nil
        return true
    }
}

/// The Watch's view of its own heart-rate pipeline, reported to the phone so
/// Copy Diagnostics can tell a silent sensor (permission, fit, session) from
/// a lost connection. Never carries BPM values.
struct WatchSensorDiagnostics: Equatable {
    enum SessionState: String {
        case idle, preparing, running, stopping, failed
    }

    /// A running session with no usable reading for this long is "silent".
    static let silentAfter: TimeInterval = 30

    var state: SessionState
    var appVersion: String
    var systemVersion: String
    var mode: String
    var sessionStartedAt: Date?
    /// Sensor readings delivered by HealthKit this session.
    var sensorReadings: Int
    /// Readings that were already older than `WatchHeartRateSample.maximumAge`
    /// when HealthKit delivered them, so were neither shown nor sent.
    var staleReadings: Int
    var lastSensorReadingAt: Date?
    var phoneAcknowledgements: Int
    var lastError: String?
    var reportedAt: Date

    /// Seconds the running session has gone without a usable reading.
    func quietDuration(at now: Date) -> TimeInterval? {
        guard state == .running, let since = lastSensorReadingAt ?? sessionStartedAt else { return nil }
        return max(0, now.timeIntervalSince(since))
    }

    func isSensorSilent(at now: Date) -> Bool {
        (quietDuration(at: now) ?? 0) >= Self.silentAfter
    }

    var dictionary: [String: Any] {
        var d: [String: Any] = [
            "state": state.rawValue, "appVersion": appVersion, "systemVersion": systemVersion,
            "mode": mode, "sensorReadings": sensorReadings, "staleReadings": staleReadings,
            "phoneAcknowledgements": phoneAcknowledgements,
            "reportedAt": reportedAt.timeIntervalSince1970
        ]
        if let sessionStartedAt { d["sessionStartedAt"] = sessionStartedAt.timeIntervalSince1970 }
        if let lastSensorReadingAt { d["lastSensorReadingAt"] = lastSensorReadingAt.timeIntervalSince1970 }
        if let lastError { d["lastError"] = String(lastError.prefix(300)) }
        return d
    }

    init(state: SessionState, appVersion: String, systemVersion: String, mode: String,
         sessionStartedAt: Date? = nil, sensorReadings: Int = 0, staleReadings: Int = 0,
         lastSensorReadingAt: Date? = nil, phoneAcknowledgements: Int = 0,
         lastError: String? = nil, reportedAt: Date) {
        self.state = state
        self.appVersion = appVersion
        self.systemVersion = systemVersion
        self.mode = mode
        self.sessionStartedAt = sessionStartedAt
        self.sensorReadings = sensorReadings
        self.staleReadings = staleReadings
        self.lastSensorReadingAt = lastSensorReadingAt
        self.phoneAcknowledgements = phoneAcknowledgements
        self.lastError = lastError
        self.reportedAt = reportedAt
    }

    /// Reads the nested diagnostics from any Watch message or context.
    init?(payload: [String: Any]) {
        guard let d = payload[WatchMessageKey.watchDiagnostics] as? [String: Any],
              let state = (d["state"] as? String).flatMap(SessionState.init(rawValue:)),
              let reported = (d["reportedAt"] as? NSNumber)?.doubleValue, reported.isFinite else { return nil }
        func date(_ key: String) -> Date? {
            guard let value = (d[key] as? NSNumber)?.doubleValue, value.isFinite else { return nil }
            return Date(timeIntervalSince1970: value)
        }
        func count(_ key: String) -> Int { max(0, (d[key] as? NSNumber)?.intValue ?? 0) }
        self.init(state: state,
                  appVersion: d["appVersion"] as? String ?? "?",
                  systemVersion: d["systemVersion"] as? String ?? "?",
                  mode: d["mode"] as? String ?? "?",
                  sessionStartedAt: date("sessionStartedAt"),
                  sensorReadings: count("sensorReadings"),
                  staleReadings: count("staleReadings"),
                  lastSensorReadingAt: date("lastSensorReadingAt"),
                  phoneAcknowledgements: count("phoneAcknowledgements"),
                  lastError: d["lastError"] as? String,
                  reportedAt: Date(timeIntervalSince1970: reported))
    }
}

/// Direct messages and application context can arrive out of order. Legacy
/// phones are accepted until this installation supplies versioned state.
struct WatchStateInbox {
    private(set) var lastRevision: Int64?
    static func nextRevision(after previous: Int64, now: Date) -> Int64 {
        // Persisted monotonic counter survives clock corrections; wall time
        // supplies a new baseline after reinstall while the Watch stays open.
        max(previous + 1, Int64(now.timeIntervalSince1970 * 1_000))
    }
    mutating func accept(_ payload: [String: Any]) -> Bool {
        // Use a fixed-width type on both iPhone and arm64_32 Watch targets.
        guard let rawRevision = payload[WatchMessageKey.stateRevision] else { return lastRevision == nil }
        guard let number = rawRevision as? NSNumber else { return false }
        let revision = number.int64Value
        guard number.doubleValue == Double(revision) else { return false }
        guard revision > 0, lastRevision.map({ revision > $0 }) ?? true else { return false }
        lastRevision = revision
        return true
    }
}

/// One recovery request every five seconds while an expected Watch feed is
/// missing. No timer/traffic is created for idle users or a healthy HR stream.
struct WatchHeartRateRefreshPolicy {
    private var lastRequest: Date?
    mutating func shouldRequest(now: Date, workoutActive: Bool, watchInstalled: Bool,
                                hasFreshReading: Bool) -> Bool {
        guard workoutActive, watchInstalled, !hasFreshReading else { lastRequest = nil; return false }
        if let lastRequest, (0..<5).contains(now.timeIntervalSince(lastRequest)) { return false }
        lastRequest = now
        return true
    }
}

/// Presentation/recovery policy only. Never use the grace period to authorize
/// controls or extend sensor freshness. Call with a monotonic clock on the main
/// queue; active workout ticks keep retries bounded without another timer.
struct WatchConnectionRecovery {
    private var disconnectedAt: TimeInterval?
    private var lastRetryAt: TimeInterval?
    private var workoutID: String?
    private(set) var showsWarning = false

    /// Returns true when the caller should retry latest-only synchronization.
    mutating func update(active: Bool, reachable: Bool, workoutID: String?,
                         now: TimeInterval) -> Bool {
        if !active || reachable || self.workoutID != workoutID {
            disconnectedAt = nil
            lastRetryAt = nil
            showsWarning = false
        }
        self.workoutID = workoutID
        guard active, !reachable else { return false }
        // Also tolerate a reset injected clock without delaying recovery forever.
        if disconnectedAt.map({ now < $0 }) ?? true {
            disconnectedAt = now
            lastRetryAt = nil
        }
        showsWarning = now - (disconnectedAt ?? now) >= 30
        guard lastRetryAt.map({ now - $0 >= 5 }) ?? true else { return false }
        lastRetryAt = now
        return true
    }
}
