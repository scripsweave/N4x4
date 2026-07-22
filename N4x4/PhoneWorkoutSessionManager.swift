// PhoneWorkoutSessionManager.swift
// iOS 26+ only: runs an HKWorkoutSession on the iPhone so system-paired
// heart-rate sensors — AirPods Pro 3 first among them — stream live readings
// into the app. AirPods deliberately do not broadcast the standard Bluetooth
// heart-rate profile, so this Apple-sanctioned path is the only way in.
//
// Mirrors the watch WorkoutManager: the session is ended WITHOUT finishing
// the builder, so no workout is saved from here — the app's manual HealthKit
// save (saveCompletedWorkoutToHealthKit) remains the single workout record.

import Foundation
import HealthKit

@available(iOS 26.0, *)
final class PhoneWorkoutSessionManager: NSObject {

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private(set) var isSessionActive = false

    /// Fresh BPM readings, delivered on the main queue. Wired by the owner
    /// into the heart-rate funnel (ingestHeartRate, source .appleSensor).
    var onReading: ((Double) -> Void)?

    // MARK: - Authorization

    /// Heart-rate read is what the live builder needs; workout share is
    /// required to create a session at all (nothing is ever saved from here).
    func requestAuthorization(completion: @escaping (Bool) -> Void) {
        guard HKHealthStore.isHealthDataAvailable(),
              let hrType = HKQuantityType.quantityType(forIdentifier: .heartRate) else {
            completion(false)
            return
        }
        healthStore.requestAuthorization(
            toShare: [HKObjectType.workoutType()],
            read:    [hrType]
        ) { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    // MARK: - Session lifecycle

    func startWorkout() {
        guard !isSessionActive else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }

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

            // prepare() spins up sensors and lets external monitors (AirPods)
            // attach; readings begin shortly after startActivity.
            session?.prepare()

            let startDate = Date()
            // IMPORTANT: startActivity must come before beginCollection (same
            // ordering constraint as the watch — the reverse order crashes).
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { _, error in
                if let error { print("[PhoneWorkoutSession] beginCollection error: \(error)") }
            }
            isSessionActive = true
        } catch {
            print("[PhoneWorkoutSession] Failed to start HKWorkoutSession: \(error)")
            session = nil
            builder = nil
        }
    }

    func stopWorkout() {
        guard isSessionActive else { return }
        session?.end()
        // isSessionActive flips to false via the delegate callback, which
        // also discards the builder so nothing is saved from this session.
    }
}

// MARK: - HKWorkoutSessionDelegate

@available(iOS 26.0, *)
extension PhoneWorkoutSessionManager: HKWorkoutSessionDelegate {

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        DispatchQueue.main.async {
            self.isSessionActive = (toState == .running)
            if toState == .ended {
                // Never save from here — the manual HealthKit save is the
                // single workout record (avoids double-logged workouts).
                self.builder?.discardWorkout()
                self.builder = nil
                self.session = nil
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("[PhoneWorkoutSession] session error: \(error)")
        DispatchQueue.main.async {
            self.isSessionActive = false
            self.builder?.discardWorkout()
            self.builder = nil
            self.session = nil
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

@available(iOS 26.0, *)
extension PhoneWorkoutSessionManager: HKLiveWorkoutBuilderDelegate {

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
            self?.onReading?(bpm)
        }
    }
}
