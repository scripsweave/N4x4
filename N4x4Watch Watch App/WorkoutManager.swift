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

    private lazy var heartRateDelivery = WatchHeartRateDelivery(
        activated: { WCSession.isSupported() && WCSession.default.activationState == .activated },
        reachable: { WCSession.default.isReachable },
        send: { message, failed in
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("[WorkoutManager] HR send failed: \(error.localizedDescription)")
                DispatchQueue.main.async { failed() }
            }
        },
        saveContext: { message in
            do { try WCSession.default.updateApplicationContext(message) }
            catch { print("[WorkoutManager] HR context failed: \(error.localizedDescription)") }
        },
        retryLater: { retry in DispatchQueue.main.asyncAfter(deadline: .now() + 2) { retry() } }
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
        healthStore.recoverActiveWorkoutSession { [weak self] recovered, _ in
            guard self != nil, let recovered else { return }
            let builder = recovered.associatedWorkoutBuilder()
            recovered.end()
            builder.discardWorkout()
        }
    }

    func startWorkout() {
        guard !isSessionActive else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .highIntensityIntervalTraining
        config.locationType = .indoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            isStopping = false
            heartRateDelivery.reset()
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self
            builder?.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: config
            )

            let startDate = Date()
            // IMPORTANT: startActivity must come before beginCollection.
            // The reverse order crashes on some watchOS versions.
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { _, error in
                if let error { print("[WorkoutManager] beginCollection error: \(error)") }
            }
            isSessionActive = true
        } catch {
            print("[WorkoutManager] Failed to start HKWorkoutSession: \(error)")
        }
    }

    func stopWorkout() {
        guard isSessionActive else { return }
        isStopping = true
        heartRateDelivery.reset()
        session?.end()
        // isSessionActive flips to false via the delegate callback.
    }

    // MARK: - HR streaming to phone

    func resendLatestHeartRate() {
        guard isSessionActive, !isStopping else { return }
        heartRateDelivery.resendLatest()
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
            guard workoutSession === self.session else { return }
            self.isSessionActive = (toState == .running)
            if toState == .ended {
                self.heartRateDelivery.reset()
                self.heartRate = 0
                self.builder = nil
                self.session = nil
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("[WorkoutManager] session error: \(error)")
        DispatchQueue.main.async {
            workoutSession.associatedWorkoutBuilder().discardWorkout()
            guard workoutSession === self.session else { return }
            self.isSessionActive = false
            self.heartRate = 0
            self.heartRateDelivery.reset()
            self.builder = nil
            self.session = nil
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {

        guard let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate),
              collectedTypes.contains(hrType) else { return }

        let unit = HKUnit.count().unitDivided(by: .minute())
        guard let statistics = workoutBuilder.statistics(for: hrType),
              let bpm = statistics.mostRecentQuantity()?.doubleValue(for: unit),
              let measuredAt = statistics.mostRecentQuantityDateInterval()?.end else { return }
        let sample = WatchHeartRateSample(bpm: bpm, measuredAt: measuredAt)

        DispatchQueue.main.async { [weak self] in
            guard let self, workoutBuilder === self.builder, !self.isStopping,
                  sample.isFresh(at: Date()) else { return }
            self.heartRate = bpm
            self.heartRateDelivery.receive(sample)
        }
    }
}
