// TimerViewModel.swift

import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import HealthKit

struct VO2DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

class TimerViewModel: ObservableObject {
    static let minimumSupportedAge = 13
    static let maximumSupportedAge = 100

    // User settings stored in UserDefaults
    @AppStorage("numberOfIntervals") var numberOfIntervals: Int = 4 {
        didSet {
            if numberOfIntervals < 1 {
                numberOfIntervals = 1
            }
            reset()
        }
    }
    @AppStorage("warmupDuration") var warmupDuration: TimeInterval = 5 * 60 {
        didSet { reset() }
    }
    @AppStorage("highIntensityDuration") var highIntensityDuration: TimeInterval = 4 * 60 {
        didSet { reset() }
    }
    @AppStorage("restDuration") var restDuration: TimeInterval = 3 * 60 {
        didSet { reset() }
    }
    @AppStorage("alarmEnabled") var alarmEnabled: Bool = true
    @AppStorage("preventSleep") var preventSleep: Bool = true
    @AppStorage("userAge") var userAge: Int = 40 {
        didSet {
            userAge = max(Self.minimumSupportedAge, min(Self.maximumSupportedAge, userAge))
        }
    }

    // Interval notifications
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false {
        didSet {
            if notificationsEnabled && !notificationPermissionRequested {
                requestNotificationPermission()
            }
        }
    }
    @AppStorage("notificationPermissionRequested") var notificationPermissionRequested: Bool = false

    // Reminder notifications
    @AppStorage("workoutRemindersEnabled") var workoutRemindersEnabled: Bool = false {
        didSet {
            if workoutRemindersEnabled {
                if !notificationPermissionRequested {
                    requestNotificationPermission()
                }
                scheduleWorkoutReminder()
            } else {
                cancelWorkoutReminder()
            }
        }
    }
    @AppStorage("workoutReminderDays") var workoutReminderDays: Int = 7 {
        didSet {
            if workoutReminderDays < 1 {
                workoutReminderDays = 1
            }
            if workoutRemindersEnabled {
                scheduleWorkoutReminder()
            }
        }
    }

    // HealthKit
    @AppStorage("healthKitEnabled") var healthKitEnabled: Bool = false
    @Published var healthAuthorizationGranted: Bool = false
    @Published var vo2DataPoints: [VO2DataPoint] = []

    private let healthStore = HKHealthStore()

    // Timer properties
    @Published var currentIntervalIndex: Int = 0
    @Published var timeRemaining: TimeInterval = 0
    @Published var isRunning: Bool = false

    // Interval counts
    @Published var highIntensityCount: Int = 0
    @Published var restCount: Int = 0

    // Completion message display control
    @Published var showCompletionMessage: Bool = false

    var intervals: [Interval] = []
    var timer: AnyCancellable?
    var player: AVAudioPlayer?
    var intervalEndTime: Date?
    var workoutStartDate: Date?

    var maximumHeartRate: Int {
        max(1, 220 - userAge)
    }

    var highIntensityTargetRange: ClosedRange<Int> {
        let lower = Int((Double(maximumHeartRate) * 0.85).rounded())
        let upper = Int((Double(maximumHeartRate) * 0.95).rounded())
        return lower...upper
    }

    var recoveryTargetRange: ClosedRange<Int> {
        let lower = Int((Double(maximumHeartRate) * 0.60).rounded())
        let upper = Int((Double(maximumHeartRate) * 0.70).rounded())
        return lower...upper
    }

    init() {
        if numberOfIntervals < 1 {
            numberOfIntervals = 4 // Default value
        }
        if workoutReminderDays < 1 {
            workoutReminderDays = 7
        }
        userAge = max(Self.minimumSupportedAge, min(Self.maximumSupportedAge, userAge))

        setupIntervals()

        if workoutRemindersEnabled {
            scheduleWorkoutReminder()
        }

        if healthKitEnabled {
            requestHealthKitAuthorizationIfNeeded()
        }
    }

    func setupIntervals() {
        intervals.removeAll()
        highIntensityCount = 0
        restCount = 0

        // Conditionally add warm-up interval
        if warmupDuration > 0 {
            let warmup = Interval(name: "Warm Up", duration: warmupDuration, type: .warmup)
            intervals.append(warmup)
        }

        // High-intensity and rest intervals
        for i in 1...numberOfIntervals {
            let highIntensity = Interval(name: "High Intensity", duration: highIntensityDuration, type: .highIntensity)
            intervals.append(highIntensity)

            if i < numberOfIntervals {
                let rest = Interval(name: "Rest", duration: restDuration, type: .rest)
                intervals.append(rest)
            }
        }

        currentIntervalIndex = 0
        timeRemaining = intervals.first?.duration ?? 0
        intervalEndTime = nil
        updateCounts()
    }

    func updateCounts() {
        guard !intervals.isEmpty else { return }
        let currentType = intervals[currentIntervalIndex].type
        switch currentType {
        case .highIntensity:
            highIntensityCount += 1
        case .rest:
            restCount += 1
        default:
            break
        }
    }

    func startTimer() {
        isRunning = true
        if workoutStartDate == nil {
            workoutStartDate = Date()
        }
        if intervalEndTime == nil {
            intervalEndTime = Date().addingTimeInterval(timeRemaining)
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
        scheduleNextIntervalNotification()

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { _ in
                self.tick()
            }
    }

    func stopTimer() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    func tick() {
        guard isRunning else { return }
        timeRemaining = intervalEndTime?.timeIntervalSinceNow ?? timeRemaining
        if timeRemaining <= 0 {
            playAlarmIfNeeded()
            moveToNextInterval()
        }
    }

    func moveToNextInterval() {
        if currentIntervalIndex + 1 < intervals.count {
            currentIntervalIndex += 1
            timeRemaining = intervals[currentIntervalIndex].duration
            intervalEndTime = Date().addingTimeInterval(timeRemaining)

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
            updateCounts()
            scheduleNextIntervalNotification()
        } else {
            stopTimer()
            intervalEndTime = nil
            showCompletionMessage = true
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])

            if workoutRemindersEnabled {
                scheduleWorkoutReminder()
            }
            if healthKitEnabled {
                saveCompletedWorkoutToHealthKit()
                fetchVO2MaxSamples()
            }
        }
    }

    func pause() {
        if isRunning {
            timeRemaining = intervalEndTime?.timeIntervalSinceNow ?? timeRemaining
            stopTimer()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
        } else {
            intervalEndTime = Date().addingTimeInterval(timeRemaining)
            scheduleNextIntervalNotification()
            startTimer()
        }
    }

    func skip() {
        playAlarmIfNeeded()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
        moveToNextInterval()
        if !isRunning {
            startTimer()
        }
    }

    func reset() {
        stopTimer()
        setupIntervals()
        isRunning = false
        showCompletionMessage = false
        intervalEndTime = nil
        workoutStartDate = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
    }

    func scheduleNextIntervalNotification() {
        guard notificationsEnabled else { return }
        guard currentIntervalIndex + 1 < intervals.count else { return }

        let nextInterval = intervals[currentIntervalIndex + 1]
        let timeInterval = max(1, timeRemaining)
        scheduleNotification(identifier: "nextInterval", title: "N4x4 Interval", body: "Next interval: \(nextInterval.name) is starting.", in: timeInterval, repeats: false)
    }

    func scheduleWorkoutReminder() {
        guard workoutRemindersEnabled else { return }
        let seconds = max(1, workoutReminderDays) * 24 * 60 * 60

        scheduleNotification(
            identifier: "workoutReminder",
            title: "Time for your N4x4 session",
            body: "It’s been \(workoutReminderDays) day(s). Ready for your next workout?",
            in: TimeInterval(seconds),
            repeats: true
        )
    }

    func cancelWorkoutReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["workoutReminder"])
    }

    func resetSettingsToDefaults() {
        numberOfIntervals = 4
        warmupDuration = 5 * 60
        highIntensityDuration = 4 * 60
        restDuration = 3 * 60
        alarmEnabled = true
        preventSleep = true
        userAge = 40

        notificationsEnabled = false
        workoutRemindersEnabled = false
        workoutReminderDays = 7

        healthKitEnabled = false
        healthAuthorizationGranted = false
        vo2DataPoints = []
        cancelWorkoutReminder()
    }

    func playAlarmIfNeeded() {
        if alarmEnabled {
            playAlarm()
        }
    }

    func playAlarm() {
        guard let url = Bundle.main.url(forResource: "alarm", withExtension: "mp3") else { return }
        do {
            player = try AVAudioPlayer(contentsOf: url)
            player?.play()
        } catch {
            print("Error playing alarm sound: \(error.localizedDescription)")
        }
    }

    // Request notification permission
    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            } else {
                DispatchQueue.main.async {
                    self.notificationPermissionRequested = true
                    if !granted {
                        self.notificationsEnabled = false
                        self.workoutRemindersEnabled = false
                    }
                }
            }
        }
    }

    // Shared notification helper
    func scheduleNotification(identifier: String, title: String, body: String, in timeInterval: TimeInterval, repeats: Bool) {
        guard notificationsEnabled || workoutRemindersEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timeInterval), repeats: repeats)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - HealthKit

    func requestHealthKitAuthorizationIfNeeded() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        guard let vo2Type = HKObjectType.quantityType(forIdentifier: .vo2Max) else { return }

        let readTypes: Set<HKObjectType> = [vo2Type, HKObjectType.workoutType()]
        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            DispatchQueue.main.async {
                self.healthAuthorizationGranted = success
                self.healthKitEnabled = success
            }

            if let error = error {
                print("HealthKit authorization error: \(error.localizedDescription)")
            }

            if success {
                self.fetchVO2MaxSamples()
            }
        }
    }

    func fetchVO2MaxSamples() {
        guard healthKitEnabled else { return }
        guard let vo2Type = HKObjectType.quantityType(forIdentifier: .vo2Max) else { return }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let query = HKSampleQuery(sampleType: vo2Type, predicate: nil, limit: 60, sortDescriptors: [sortDescriptor]) { _, samples, error in
            if let error = error {
                print("VO2 fetch error: \(error.localizedDescription)")
                return
            }

            let unit = HKUnit(from: "mL/kg*min")
            let mapped = (samples as? [HKQuantitySample])?.map { sample in
                VO2DataPoint(date: sample.startDate, value: sample.quantity.doubleValue(for: unit))
            } ?? []

            DispatchQueue.main.async {
                self.vo2DataPoints = mapped
            }
        }

        healthStore.execute(query)
    }

    func saveCompletedWorkoutToHealthKit() {
        guard healthKitEnabled, healthAuthorizationGranted else { return }

        let endDate = Date()
        let startDate = workoutStartDate ?? endDate.addingTimeInterval(-totalWorkoutDuration())
        let duration = endDate.timeIntervalSince(startDate)

        let workout = HKWorkout(
            activityType: .highIntensityIntervalTraining,
            start: startDate,
            end: endDate,
            duration: duration,
            totalEnergyBurned: nil,
            totalDistance: nil,
            metadata: [HKMetadataKeyIndoorWorkout: true]
        )

        healthStore.save(workout) { success, error in
            if let error = error {
                print("Workout save error: \(error.localizedDescription)")
            }
            if !success {
                print("Workout save failed")
            }
        }
    }

    func totalWorkoutDuration() -> TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }
}
