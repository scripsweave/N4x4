// WorkoutManager.swift
// watchOS only.
// Runs an HKWorkoutSession to collect real-time heart rate, and streams each
// reading to the iPhone over WCSession. Starting a workout session is what
// unlocks high-frequency optical-HR sampling and keeps the Watch app alive in
// the background for the duration of the workout.

import Foundation
import HealthKit
import WatchConnectivity
import Combine   // @Published / ObservableObject — not transitively available on watchOS

final class WorkoutManager: NSObject, ObservableObject {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var isStopping = false
    private var lifecycle = WatchWorkoutSessionLifecycle()
    private var preparation = WatchSessionPreparation()
    private var preparationStallWork: DispatchWorkItem?
    private var recoveringSession: HKWorkoutSession?
    private var sessionToken = 0
    private var workoutID: String?
    private var expiryWork: DispatchWorkItem?
    private var silenceWork: DispatchWorkItem?
    private var energyReportID: UUID?
    private var energyReportStart: Double?
    private var queryingEnergy: Set<UUID> = []
    /// Open calorie reports already announced this launch. Once delivered,
    /// re-sending on every five-second phone HR request was pure traffic.
    private var announcedEnergyReports: Set<UUID> = []
    // Diagnostics for the phone (no BPM). Kept after a session ends so the
    // phone can still see what the last session did.
    private var sessionStartedAt: Date?
    private var sensorReadings = 0
    private var staleReadings = 0
    private var lastSensorReadingAt: Date?
    private var phoneAcknowledgements = 0
    private var lastDiagnosticsPublish: TimeInterval = -.infinity
    /// Newest HR fallback written to application context (see writeContext).
    private var contextHeartRate: [String: Any]?
    var onReading: ((WatchHeartRateSample) -> Void)?
    /// "Phone-led" / "Watch-led", supplied by the root for diagnostics.
    var describeMode: (() -> String)?
    @Published private(set) var latestReading: WatchHeartRateSample?
    @Published private(set) var lastPhoneAcknowledgement: Date?
    @Published private(set) var lastSessionError: String?
    /// The session is running but the sensor has produced no usable reading
    /// for `WatchSensorDiagnostics.silentAfter` seconds.
    @Published private(set) var sensorSilent = false
    var hasHeartRateIssue: Bool { lastSessionError != nil || sensorSilent }

    #if DEBUG
    /// Layout checks for the silent-sensor guidance (`-demoSensorSilent`).
    func injectDemoSensorSilent() {
        heartRate = 0
        sensorSilent = true
    }
    #endif

    private lazy var heartRateDelivery = WatchHeartRateDelivery(
        activated: { WCSession.isSupported() && WCSession.default.activationState == .activated },
        reachable: { WCSession.default.isReachable },
        send: { [weak self] message, completed in
            WCSession.default.sendMessage(self?.addingEnergySession(to: message) ?? message, replyHandler: { reply in
                let acknowledged = reply[WatchMessageKey.hrAcknowledgement] as? Double
                let sent = message[WatchMessageKey.hrTimestamp] as? Double
                DispatchQueue.main.async { completed(acknowledged != nil && acknowledged == sent) }
            }, errorHandler: { error in
                print("[WorkoutManager] HR send failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completed(false) }
            })
        },
        saveContext: { [weak self] message in
            guard let self else { return }
            self.writeContext(heartRate: self.addingEnergySession(to: message))
        },
        retryLater: { retry in DispatchQueue.main.asyncAfter(deadline: .now() + 2) { retry() } },
        acknowledged: { [weak self] _ in
            self?.lastPhoneAcknowledgement = Date()
            self?.phoneAcknowledgements += 1
        }
    )

    @Published var heartRate: Double = 0
    @Published var isSessionActive: Bool = false

    // MARK: - Authorization

    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            completion(false)
            return
        }
        let hrType     = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        healthStore.requestAuthorization(
            toShare: [HKObjectType.workoutType(), energyType],
            read:    [hrType, energyType, HKObjectType.workoutType()]
        ) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - Session lifecycle

    /// Cold-launch cleanup: if a previous run left a workout session behind
    /// (crash, force-quit mid-workout), watchOS offers it back for recovery —
    /// and would otherwise finalize it as a workout in Health. We never save
    /// from the watch, so end and discard it. Call once at app launch, before
    /// any session starts.
    func discardAbandonedSession() {
        guard !lifecycle.prepared,
              let token = preparation.begin(now: ProcessInfo.processInfo.systemUptime) else { return }
        // A superseded attempt's recovered session is still discarded by the
        // delegate when it ends; it just no longer gates this attempt.
        recoveringSession = nil
        schedulePreparationStallCheck(token: token)
        publishDiagnostics(force: true)
        requestAuthorization { [weak self] _ in
            guard let self, self.preparation.token == token, self.preparation.isPreparing else { return }
            guard self.healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
                _ = self.preparation.end(token: token)
                self.lastSessionError = "Allow N4x4 to access Workouts in Health settings on your Watch."
                self.publishDiagnostics(force: true)
                return
            }
            self.recoverAbandonedSession(token: token)
        }
    }

    private func recoverAbandonedSession(token: Int) {
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            DispatchQueue.main.async {
                guard let self else { return }
                // A superseded attempt does nothing: the newer attempt runs its
                // own recovery, and a late result could name a live session.
                guard self.preparation.token == token, self.preparation.isPreparing else { return }
                if let error {
                    _ = self.preparation.end(token: token)
                    self.lastSessionError = "Couldn’t check the previous Watch workout: \(error.localizedDescription)"
                    self.publishDiagnostics(force: true)
                    return
                }
                guard let recovered else { self.finishPreparation(token: token); return }
                recovered.associatedWorkoutBuilder().discardWorkout()
                guard recovered.state != .ended else { self.finishPreparation(token: token); return }
                self.recoveringSession = recovered
                recovered.delegate = self
                recovered.end()
                // Wait for .ended before allowing a new sensor session.
            }
        }
    }

    private func finishPreparation(token: Int) {
        guard preparation.end(token: token) else { return }
        preparationStallWork?.cancel()
        preparationStallWork = nil
        recoveringSession = nil
        lastSessionError = nil
        recoverEnergyReports()
        perform(lifecycle.preparationFinished())
        publishDiagnostics(force: true)
    }

    /// Surfaces a stalled startup with an error, which also shows Retry Heart
    /// Rate. The attempt itself stays valid: a late callback still completes it.
    private func schedulePreparationStallCheck(token: Int) {
        preparationStallWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self,
                  self.preparation.isStalled(token: token, now: ProcessInfo.processInfo.systemUptime) else { return }
            self.lastSessionError = self.recoveringSession == nil
                ? "Still waiting for Health access. Check your Watch for a Health request, then tap Retry Heart Rate."
                : "The previous Watch workout is still closing. Tap Retry Heart Rate."
            self.publishDiagnostics(force: true)
        }
        preparationStallWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + WatchSessionPreparation.stallTimeout + 0.1, execute: work)
    }

    func updateWorkout(sessionStarted: Bool, complete: Bool, workoutID: String?) {
        perform(lifecycle.desire(sessionStarted: sessionStarted, complete: complete, workoutID: workoutID))
    }

    func refreshOnForeground() {
        discardAbandonedSession()
        recoverEnergyReports()
        perform(lifecycle.retry())
        expireReadingIfNeeded()
        resendLatestHeartRate()
    }

    /// Retry Heart Rate: re-runs a stalled startup, restarts a failed session,
    /// and restarts a running session whose sensor has gone silent.
    func retryHeartRate() {
        if sensorSilent, session != nil, !isStopping {
            sensorSilent = false
            perform(lifecycle.restart())
        }
        refreshOnForeground()
    }

    private func perform(_ action: WatchWorkoutSessionLifecycle.Action?) {
        switch action {
        case let .start(id, token): startWorkout(workoutID: id, token: token)
        case .stop: stopWorkout()
        case nil: break
        }
    }

    private func startWorkout(workoutID: String, token: Int) {
        sessionToken = token
        energyReportID = nil
        energyReportStart = nil
        sessionStartedAt = Date()
        sensorReadings = 0
        staleReadings = 0
        lastSensorReadingAt = nil
        phoneAcknowledgements = 0
        sensorSilent = false
        self.workoutID = workoutID == "legacy" ? nil : workoutID
        let config = HKWorkoutConfiguration()
        config.activityType = .highIntensityIntervalTraining
        config.locationType = .indoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            isStopping = false
            clearReading()
            lastSessionError = nil
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )

            let startDate = Date()
            if let id = UUID(uuidString: workoutID) {
                let report = WorkoutEnergyReport(id: UUID(), workoutID: id,
                                                 start: startDate.timeIntervalSince1970,
                                                 end: startDate.timeIntervalSince1970)
                do {
                    try WorkoutEnergyStore.shared.save(report)
                    energyReportID = report.id
                    energyReportStart = report.start
                    flushEnergyReports()
                } catch { print("[WorkoutManager] Couldn’t checkpoint calories: \(error)") }
            }
            // IMPORTANT: startActivity must come before beginCollection.
            // The reverse order crashes on some watchOS versions.
            session?.startActivity(with: startDate)
            let startedSession = session
            builder?.beginCollection(withStart: startDate) { [weak self] _, error in
                guard let error else { return }
                DispatchQueue.main.async {
                    guard let self, self.session === startedSession else { return }
                    self.lastSessionError = "Couldn’t collect Watch heart rate: \(error.localizedDescription)"
                    self.stopWorkout()
                }
            }
            isSessionActive = true
            scheduleSilenceCheck()
            publishDiagnostics(force: true)
        } catch {
            lastSessionError = "Couldn’t start Watch heart rate: \(error.localizedDescription)"
            session = nil
            builder = nil
            isSessionActive = false
            perform(lifecycle.ended(token: token, failed: true))
            publishDiagnostics(force: true)
        }
    }

    private func stopWorkout() {
        guard let session else { return }
        isStopping = true
        checkpointEnergy(at: Date())
        clearReading()
        session.end()
        publishDiagnostics(force: true)
        // isSessionActive flips to false via the delegate callback.
    }

    // MARK: - HR streaming to phone

    func resendLatestHeartRate() {
        recoverEnergyReports()
        // The phone asks every five seconds while it expects HR and has none;
        // answer with the Watch's own view so the gap can be diagnosed.
        publishDiagnostics()
        guard isSessionActive, !isStopping else { return }
        heartRateDelivery.resendLatest()
    }

    /// Cached at session start: this runs for every HR send, and reading the
    /// report back from disk each time was needless main-thread I/O.
    private func addingEnergySession(to message: [String: Any]) -> [String: Any] {
        guard let id = energyReportID, let start = energyReportStart else { return message }
        var message = message
        message[WatchMessageKey.energySessionID] = id.uuidString
        message[WatchMessageKey.energySessionStart] = start
        return message
    }

    // MARK: - Diagnostics (no BPM)

    private static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }()

    private var diagnosticsState: WatchSensorDiagnostics.SessionState {
        if preparation.isPreparing { return .preparing }
        if session != nil { return isStopping ? .stopping : .running }
        return lastSessionError == nil ? .idle : .failed
    }

    private func currentDiagnostics(now: Date = Date()) -> WatchSensorDiagnostics {
        WatchSensorDiagnostics(state: diagnosticsState,
                               appVersion: Self.appVersion,
                               systemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
                               mode: describeMode?() ?? "?",
                               sessionStartedAt: sessionStartedAt,
                               sensorReadings: sensorReadings,
                               staleReadings: staleReadings,
                               lastSensorReadingAt: lastSensorReadingAt,
                               phoneAcknowledgements: phoneAcknowledgements,
                               lastError: lastSessionError,
                               reportedAt: now)
    }

    /// State changes publish immediately; counters at most every ten seconds.
    /// Live message when reachable, and always the latest-only context so the
    /// phone still learns it after the Watch app has gone quiet.
    private func publishDiagnostics(force: Bool = false) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || now - lastDiagnosticsPublish >= 10 else { return }
        lastDiagnosticsPublish = now
        if WCSession.default.isReachable {
            WCSession.default.sendMessage([WatchMessageKey.messageType: WatchMessageKey.watchDiagnostics,
                                           WatchMessageKey.watchDiagnostics: currentDiagnostics().dictionary],
                                          replyHandler: nil, errorHandler: nil)
        }
        writeContext(heartRate: nil)
    }

    /// The application context is one latest-only dictionary: the newest HR
    /// fallback while still fresh, plus the current diagnostics. Writing
    /// diagnostics alone must not wipe an undelivered fresh reading.
    private func writeContext(heartRate message: [String: Any]?) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        if let message { contextHeartRate = message }
        var context: [String: Any]
        if let hr = contextHeartRate, WatchHeartRateSample(message: hr)?.isFresh(at: Date()) == true {
            context = hr
        } else {
            contextHeartRate = nil
            context = [WatchMessageKey.messageType: WatchMessageKey.watchDiagnostics]
        }
        context[WatchMessageKey.watchDiagnostics] = currentDiagnostics().dictionary
        do { try WCSession.default.updateApplicationContext(context) }
        catch { print("[WorkoutManager] Context update failed: \(error.localizedDescription)") }
    }

    /// Re-armed by every usable reading; fires once the running session has
    /// been quiet for `silentAfter`, which shows guidance and Retry.
    private func scheduleSilenceCheck() {
        silenceWork?.cancel()
        silenceWork = nil
        guard session != nil, !isStopping, let since = lastSensorReadingAt ?? sessionStartedAt else { return }
        let delay = max(0, WatchSensorDiagnostics.silentAfter - Date().timeIntervalSince(since))
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.session != nil, !self.isStopping else { return }
            if self.currentDiagnostics().isSensorSilent(at: Date()) {
                if !self.sensorSilent {
                    self.sensorSilent = true
                    self.publishDiagnostics(force: true)
                }
            } else {
                self.scheduleSilenceCheck()
            }
        }
        silenceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.1, execute: work)
    }

    private func checkpointEnergy(at date: Date) {
        guard let id = energyReportID, let workoutID, let workout = UUID(uuidString: workoutID),
              var report = try? WorkoutEnergyStore.shared.reports(for: workout).first(where: { $0.id == id }),
              !report.finalized else { return }
        report.end = max(report.start, date.timeIntervalSince1970)
        do { try WorkoutEnergyStore.shared.save(report) }
        catch { print("[WorkoutManager] Couldn’t checkpoint calories: \(error)") }
    }

    private func finishEnergy(at date: Date) {
        checkpointEnergy(at: date)
        guard let id = energyReportID, let workoutID, let workout = UUID(uuidString: workoutID),
              let report = try? WorkoutEnergyStore.shared.reports(for: workout).first(where: { $0.id == id }) else { return }
        energyReportID = nil
        collectEnergy(report)
    }

    /// The session's sensor samples already exist in Health, even though its
    /// workout builder is discarded. Send identifiers rather than new samples.
    private func collectEnergy(_ report: WorkoutEnergyReport) {
        guard !report.finalized, !queryingEnergy.contains(report.id), let end = report.end else { return }
        queryingEnergy.insert(report.id)
        let dates = HKQuery.predicateForSamples(withStart: Date(timeIntervalSince1970: report.start),
                                               end: Date(timeIntervalSince1970: end),
                                               options: [.strictStartDate, .strictEndDate])
        let device = HKQuery.predicateForObjects(from: Set([HKDevice.local()]))
        let query = HKSampleQuery(sampleType: HKQuantityType(.activeEnergyBurned),
                                  predicate: NSCompoundPredicate(andPredicateWithSubpredicates: [dates, device]),
                                  limit: HKObjectQueryNoLimit, sortDescriptors: nil) { [weak self] _, samples, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.queryingEnergy.remove(report.id)
                guard error == nil else { return } // Retained for the next foreground/reconnect.
                var sealed = report
                sealed.samples = (samples as? [HKQuantitySample] ?? []).map {
                    WorkoutEnergySample(id: $0.uuid, start: $0.startDate.timeIntervalSince1970,
                                        end: $0.endDate.timeIntervalSince1970,
                                        kilocalories: $0.quantity.doubleValue(for: .kilocalorie()))
                }.filter(\.isValid)
                sealed.finalized = true
                do {
                    try WorkoutEnergyStore.shared.save(sealed)
                    self.flushEnergyReports()
                } catch { print("[WorkoutManager] Couldn’t retain calories: \(error)") }
            }
        }
        healthStore.execute(query)
    }

    private func recoverEnergyReports() {
        guard let reports = try? WorkoutEnergyStore.shared.allReports() else { return }
        for report in reports where !report.finalized && report.id != energyReportID { collectEnergy(report) }
        flushEnergyReports()
    }

    func flushEnergyReports() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              let reports = try? WorkoutEnergyStore.shared.allReports() else { return }
        let transfers = WCSession.default.outstandingUserInfoTransfers
        for report in reports {
            if report.finalized {
                guard !WCSession.default.outstandingFileTransfers.contains(where: {
                    $0.file.metadata?[WatchMessageKey.energySessionID] as? String == report.id.uuidString
                }) else { continue }
                // A full workout's UUID manifest can exceed the message-size
                // limit. File transfer is durable and has no small-packet cap.
                do {
                    let directory = WorkoutEnergyStore.shared.directory.appendingPathComponent("Outgoing", isDirectory: true)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    // A late completion from an earlier attempt must only
                    // remove its own file, never a newly queued retry's file.
                    let file = directory.appendingPathComponent(UUID().uuidString + ".json")
                    try JSONEncoder().encode(report).write(to: file, options: .atomic)
                    WCSession.default.transferFile(file, metadata: [
                        WatchMessageKey.messageType: WatchMessageKey.energyReport,
                        WatchMessageKey.workoutID: report.workoutID.uuidString,
                        WatchMessageKey.energySessionID: report.id.uuidString
                    ])
                } catch { print("[WorkoutManager] Couldn’t queue calories: \(error)") }
                continue
            }
            guard !announcedEnergyReports.contains(report.id), !transfers.contains(where: {
                $0.userInfo[WatchMessageKey.messageType] as? String == WatchMessageKey.energyReport
                    && $0.userInfo[WatchMessageKey.energySessionID] as? String == report.id.uuidString
                    && $0.userInfo[WatchMessageKey.energyFinalized] as? Bool == report.finalized
            }), let data = try? JSONEncoder().encode(report) else { continue }
            // transferUserInfo is guaranteed; one announcement per launch is enough.
            announcedEnergyReports.insert(report.id)
            let message: [String: Any] = [WatchMessageKey.messageType: WatchMessageKey.energyReport,
                                         WatchMessageKey.energySessionID: report.id.uuidString,
                                         WatchMessageKey.workoutID: report.workoutID.uuidString,
                                         WatchMessageKey.energyFinalized: report.finalized, WatchMessageKey.workoutRecord: data]
            WCSession.default.transferUserInfo(message)
            // Announce the expectation before a short phone-led workout ends.
            if WCSession.default.isReachable {
                WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: nil)
            }
        }
    }

    func acknowledgeEnergy(_ message: [String: Any]) {
        guard let rawID = message[WatchMessageKey.energySessionID] as? String, let id = UUID(uuidString: rawID),
              let rawWorkout = message[WatchMessageKey.workoutID] as? String, let workout = UUID(uuidString: rawWorkout),
              let report = try? WorkoutEnergyStore.shared.reports(for: workout).first(where: { $0.id == id }),
              report.finalized else { return }
        try? WorkoutEnergyStore.shared.remove(sessionID: id, workoutID: workout)
    }
    private func clearReading() {
        expiryWork?.cancel()
        expiryWork = nil
        latestReading = nil
        heartRate = 0
        lastPhoneAcknowledgement = nil
        heartRateDelivery.reset()
    }

    private func expireReadingIfNeeded() {
        guard let reading = latestReading, !reading.isFresh(at: Date()) else { return }
        latestReading = nil
        heartRate = 0
    }

    private func receive(_ sample: WatchHeartRateSample) {
        sensorReadings += 1
        guard sample.isFresh(at: Date()) else {
            // Dropping is the freshness rule; counting it tells a sensor that
            // delivers late batches apart from one that delivers nothing.
            staleReadings += 1
            publishDiagnostics(force: staleReadings == 1)
            return
        }
        guard latestReading.map({ sample.measuredAt > $0.measuredAt || !$0.isFresh(at: Date()) }) ?? true else { return }
        let changed = lastSensorReadingAt == nil || sensorSilent
        lastSensorReadingAt = sample.measuredAt
        sensorSilent = false
        publishDiagnostics(force: changed)
        scheduleSilenceCheck()
        latestReading = sample
        heartRate = sample.bpm
        onReading?(sample)
        heartRateDelivery.receive(sample)
        expiryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.expireReadingIfNeeded() }
        expiryWork = work
        let delay = max(0, WatchHeartRateSample.maximumAge - Date().timeIntervalSince(sample.measuredAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 0.05, execute: work)
    }

}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        DispatchQueue.main.async {
            // Discard even a superseded session: ignoring its late callback
            // must not let watchOS save a second workout to Health.
            if toState == .ended {
                workoutSession.associatedWorkoutBuilder().discardWorkout()
            }
            if workoutSession === self.recoveringSession {
                if toState == .ended { self.finishPreparation(token: self.preparation.token) }
                return
            }
            guard workoutSession === self.session else { return }
            self.isSessionActive = toState != .ended && toState != .stopped
            if toState == .stopped { workoutSession.end() }
            if toState == .ended {
                self.finishEnergy(at: date)
                if !self.isStopping {
                    self.lastSessionError = "The Watch heart-rate session ended. Tap Retry Heart Rate to reconnect."
                }
                self.clearReading()
                self.silenceWork?.cancel()
                self.sensorSilent = false
                self.builder = nil
                self.session = nil
                self.isStopping = false
                self.perform(self.lifecycle.ended(token: self.sessionToken))
                self.publishDiagnostics(force: true)
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("[WorkoutManager] session error: \(error)")
        DispatchQueue.main.async {
            workoutSession.associatedWorkoutBuilder().discardWorkout()
            if workoutSession === self.recoveringSession {
                self.recoveringSession = nil
                _ = self.preparation.end(token: self.preparation.token)
                self.lastSessionError = "Couldn’t close the previous Watch workout: \(error.localizedDescription)"
                self.publishDiagnostics(force: true)
                return
            }
            guard workoutSession === self.session else { return }
            self.finishEnergy(at: Date())
            self.isSessionActive = false
            self.clearReading()
            self.silenceWork?.cancel()
            self.sensorSilent = false
            self.builder = nil
            self.session = nil
            self.isStopping = false
            self.lastSessionError = "Watch heart rate stopped: \(error.localizedDescription)"
            self.perform(self.lifecycle.ended(token: self.sessionToken, failed: true))
            self.publishDiagnostics(force: true)
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {

        if collectedTypes.contains(HKQuantityType(.activeEnergyBurned)) {
            DispatchQueue.main.async { [weak self] in
                guard let self, workoutBuilder === self.builder, !self.isStopping else { return }
                self.checkpointEnergy(at: Date())
            }
        }

        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType) else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let statistics = workoutBuilder.statistics(for: hrType),
              let bpm = statistics.mostRecentQuantity()?.doubleValue(for: unit),
              let measuredAt = statistics.mostRecentQuantityDateInterval()?.end else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, workoutBuilder === self.builder, !self.isStopping,
                  self.isSessionActive else { return }
            let sample = WatchHeartRateSample(bpm: bpm, measuredAt: measuredAt, workoutID: self.workoutID)
            self.receive(sample)
        }
    }
}
