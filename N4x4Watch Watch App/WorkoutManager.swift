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
        session?.end()
        // isSessionActive flips to false via the delegate callback.
    }

    // MARK: - HR streaming to phone

    private func streamHeartRate(_ bpm: Double) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }

        WCSession.default.sendMessage(
            [
                WatchMessageKey.messageType: WatchMessageKey.heartRate,
                WatchMessageKey.hrBPM:       bpm,
                WatchMessageKey.hrTimestamp: Date().timeIntervalSince1970,
            ],
            replyHandler: nil,
            errorHandler: nil
        )
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        DispatchQueue.main.async {
            self.isSessionActive = (toState == .running)
            if toState == .ended {
                self.heartRate = 0
                // Never save from here — merely ending the session is NOT
                // enough, watchOS finalizes the collected data as a workout,
                // duplicating the phone's manual HealthKit save (the single
                // workout record). Discard explicitly, like the phone manager.
                self.builder?.discardWorkout()
                self.builder = nil
                self.session = nil
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("[WorkoutManager] session error: \(error)")
        DispatchQueue.main.async {
            self.isSessionActive = false
            self.builder?.discardWorkout()
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
        guard let bpm = workoutBuilder
                .statistics(for: hrType)?
                .mostRecentQuantity()?
                .doubleValue(for: unit) else { return }

        DispatchQueue.main.async { [weak self] in
            self?.heartRate = bpm
            self?.streamHeartRate(bpm)
        }
    }
}
