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
    private var isPreparing = false
    private var recoveringSession: HKWorkoutSession?
    private var sessionToken = 0
    private var workoutID: String?
    private var expiryWork: DispatchWorkItem?
    private var energyReportID: UUID?
    private var queryingEnergy: Set<UUID> = []
    var onReading: ((WatchHeartRateSample) -> Void)?
    @Published private(set) var latestReading: WatchHeartRateSample?
    @Published private(set) var lastPhoneAcknowledgement: Date?
    @Published private(set) var lastSessionError: String?

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
            do { try WCSession.default.updateApplicationContext(self?.addingEnergySession(to: message) ?? message) }
            catch { print("[WorkoutManager] HR context failed: \(error.localizedDescription)") }
        },
        retryLater: { retry in DispatchQueue.main.asyncAfter(deadline: .now() + 2) { retry() } },
        acknowledged: { [weak self] _ in self?.lastPhoneAcknowledgement = Date() }
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
        guard !lifecycle.prepared, !isPreparing else { return }
        isPreparing = true
        requestAuthorization { [weak self] _ in
            guard let self else { return }
            guard self.healthStore.authorizationStatus(for: .workoutType()) == .sharingAuthorized else {
                self.isPreparing = false
                self.lastSessionError = "Allow N4x4 to access Workouts in Health settings on your Watch."
                return
            }
            self.recoverAbandonedSession()
        }
    }

    private func recoverAbandonedSession() {
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.isPreparing = false
                    self.lastSessionError = "Couldn’t check the previous Watch workout: \(error.localizedDescription)"
                    return
                }
                guard let recovered else { self.finishPreparation(); return }
                recovered.associatedWorkoutBuilder().discardWorkout()
                guard recovered.state != .ended else { self.finishPreparation(); return }
                self.recoveringSession = recovered
                recovered.delegate = self
                recovered.end()
                // Wait for .ended before allowing a new sensor session.
            }
        }
    }

    private func finishPreparation() {
        recoveringSession = nil
        isPreparing = false
        lastSessionError = nil
        recoverEnergyReports()
        perform(lifecycle.preparationFinished())
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
        } catch {
            lastSessionError = "Couldn’t start Watch heart rate: \(error.localizedDescription)"
            session = nil
            builder = nil
            isSessionActive = false
            perform(lifecycle.ended(token: token, failed: true))
        }
    }

    private func stopWorkout() {
        guard let session else { return }
        isStopping = true
        checkpointEnergy(at: Date())
        clearReading()
        session.end()
        // isSessionActive flips to false via the delegate callback.
    }

    // MARK: - HR streaming to phone

    func resendLatestHeartRate() {
        recoverEnergyReports()
        guard isSessionActive, !isStopping else { return }
        heartRateDelivery.resendLatest()
    }

    private func addingEnergySession(to message: [String: Any]) -> [String: Any] {
        guard let id = energyReportID, let workoutID, let workout = UUID(uuidString: workoutID),
              let report = try? WorkoutEnergyStore.shared.reports(for: workout).first(where: { $0.id == id }) else { return message }
        var message = message
        message[WatchMessageKey.energySessionID] = id.uuidString
        message[WatchMessageKey.energySessionStart] = report.start
        return message
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
            guard !transfers.contains(where: {
                $0.userInfo[WatchMessageKey.messageType] as? String == WatchMessageKey.energyReport
                    && $0.userInfo[WatchMessageKey.energySessionID] as? String == report.id.uuidString
                    && $0.userInfo[WatchMessageKey.energyFinalized] as? Bool == report.finalized
            }), let data = try? JSONEncoder().encode(report) else { continue }
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
        guard sample.isFresh(at: Date()),
              latestReading.map({ sample.measuredAt > $0.measuredAt || !$0.isFresh(at: Date()) }) ?? true else { return }
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
                if toState == .ended { self.finishPreparation() }
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
                self.builder = nil
                self.session = nil
                self.perform(self.lifecycle.ended(token: self.sessionToken))
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
                self.isPreparing = false
                self.lastSessionError = "Couldn’t close the previous Watch workout: \(error.localizedDescription)"
                return
            }
            guard workoutSession === self.session else { return }
            self.finishEnergy(at: Date())
            self.isSessionActive = false
            self.clearReading()
            self.builder = nil
            self.session = nil
            self.lastSessionError = "Watch heart rate stopped: \(error.localizedDescription)"
            self.perform(self.lifecycle.ended(token: self.sessionToken, failed: true))
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
