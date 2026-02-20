// TimerViewModel.swift

import SwiftUI
import Combine
import AVFoundation
import UserNotifications
import HealthKit

enum PermissionState: Equatable {
    case unknown
    case notDetermined
    case granted
    case denied
    case unavailable
}

enum WorkoutReminderMode: String, CaseIterable, Identifiable {
    case everyXDays
    case weeklyWeekday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .everyXDays: return "Every X days"
        case .weeklyWeekday: return "Weekly on weekday"
        }
    }
}



enum WorkoutType: String, CaseIterable, Identifiable, Codable {
    case norwegian4x4 = "Norwegian 4x4"
    case run = "Run"
    case cycle = "Cycle"
    case rowing = "Rowing"
    case treadmill = "Treadmill"
    case hillSprints = "Hill sprints"
    case stairs = "Stairs"
    case jumpRope = "Jump rope"
    case circuit = "Circuit"
    case sports = "Sports"
    case other = "Other"

    var id: String { rawValue }
}

struct WorkoutLogEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let completedAt: Date
    let workoutType: WorkoutType
    let notes: String

    init(id: UUID = UUID(), completedAt: Date = Date(), workoutType: WorkoutType, notes: String) {
        self.id = id
        self.completedAt = completedAt
        self.workoutType = workoutType
        self.notes = notes
    }
}

private struct LegacyWorkoutLogEntryV1: Decodable {
    let id: UUID?
    let completedAt: Date
}

private struct LegacyWorkoutLogEntryV2: Decodable {
    let id: UUID?
    let completedAt: Date
    let workoutType: String?
    let notes: String?
}

struct VO2DataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

class TimerViewModel: ObservableObject {
    static let minimumSupportedAge = 13
    static let maximumSupportedAge = 100
    private static let missedWorkoutFollowUpIdentifier = "workoutReminderFollowup"

    // User settings stored in UserDefaults
    @AppStorage("numberOfIntervals") var numberOfIntervals: Int = 4 {
        didSet {
            let sanitized = max(1, numberOfIntervals)
            if sanitized != numberOfIntervals {
                numberOfIntervals = sanitized
                return
            }
            guard oldValue != numberOfIntervals else { return }
            reset()
        }
    }
    @AppStorage("warmupDuration") var warmupDuration: TimeInterval = 5 * 60 {
        didSet {
            guard oldValue != warmupDuration else { return }
            reset()
        }
    }
    @AppStorage("highIntensityDuration") var highIntensityDuration: TimeInterval = 4 * 60 {
        didSet {
            guard oldValue != highIntensityDuration else { return }
            reset()
        }
    }
    @AppStorage("restDuration") var restDuration: TimeInterval = 3 * 60 {
        didSet {
            guard oldValue != restDuration else { return }
            reset()
        }
    }
    @AppStorage("alarmEnabled") var alarmEnabled: Bool = true
    @AppStorage("preventSleep") var preventSleep: Bool = true
    @AppStorage("userAge") var userAge: Int = 40 {
        didSet {
            let sanitized = max(Self.minimumSupportedAge, min(Self.maximumSupportedAge, userAge))
            if sanitized != userAge {
                userAge = sanitized
                return
            }
            guard oldValue != userAge else { return }
        }
    }

    // Interval notifications
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = false {
        didSet {
            guard oldValue != notificationsEnabled else { return }
            if notificationsEnabled {
                ensureNotificationPermissionForToggles()
            }
        }
    }
    @AppStorage("notificationPermissionRequested") var notificationPermissionRequested: Bool = false

    // Reminder notifications
    @AppStorage("workoutRemindersEnabled") var workoutRemindersEnabled: Bool = false {
        didSet {
            guard oldValue != workoutRemindersEnabled else { return }
            if workoutRemindersEnabled {
                ensureNotificationPermissionForToggles()
                scheduleWorkoutReminder()
            } else {
                cancelWorkoutReminder()
            }
        }
    }
    @AppStorage("workoutReminderDays") var workoutReminderDays: Int = 7 {
        didSet {
            let sanitized = max(1, workoutReminderDays)
            if sanitized != workoutReminderDays {
                workoutReminderDays = sanitized
                return
            }
            guard oldValue != workoutReminderDays else { return }
            if workoutRemindersEnabled, workoutReminderMode == .everyXDays {
                scheduleWorkoutReminder()
            }
        }
    }
    @AppStorage("workoutReminderMode") private var workoutReminderModeRaw: String = WorkoutReminderMode.everyXDays.rawValue {
        didSet {
            let sanitized = WorkoutReminderMode(rawValue: workoutReminderModeRaw)?.rawValue ?? WorkoutReminderMode.everyXDays.rawValue
            if sanitized != workoutReminderModeRaw {
                workoutReminderModeRaw = sanitized
                return
            }
            guard oldValue != workoutReminderModeRaw else { return }

            if workoutReminderMode == .weeklyWeekday, workoutReminderWeekday == 0 {
                workoutReminderWeekday = Self.defaultWorkoutReminderWeekday()
                return
            }

            if workoutRemindersEnabled {
                scheduleWorkoutReminder()
            }
        }
    }
    @AppStorage("workoutReminderWeekday") var workoutReminderWeekday: Int = 0 {
        didSet {
            let sanitized = (1...7).contains(workoutReminderWeekday) ? workoutReminderWeekday : 0
            if sanitized != workoutReminderWeekday {
                workoutReminderWeekday = sanitized
                return
            }
            guard oldValue != workoutReminderWeekday else { return }
            if workoutRemindersEnabled, workoutReminderMode == .weeklyWeekday {
                scheduleWorkoutReminder()
            }
        }
    }


    @AppStorage("workoutLogEntriesData") private var workoutLogEntriesData: String = "[]"
    @Published var workoutLogEntries: [WorkoutLogEntry] = []
    @Published var selectedWorkoutType: WorkoutType = .norwegian4x4
    @Published var workoutNotesDraft: String = ""
    @Published var showPostWorkoutSummary: Bool = false

    // HealthKit
    @AppStorage("healthKitEnabled") var healthKitEnabled: Bool = false
    @Published var healthAuthorizationGranted: Bool = false
    @Published var vo2DataPoints: [VO2DataPoint] = []

    @Published var notificationPermissionState: PermissionState = .unknown
    @Published var healthKitPermissionState: PermissionState = .unknown

    var workoutReminderMode: WorkoutReminderMode {
        get { WorkoutReminderMode(rawValue: workoutReminderModeRaw) ?? .everyXDays }
        set {
            let sanitized = newValue
            guard workoutReminderModeRaw != sanitized.rawValue else { return }
            workoutReminderModeRaw = sanitized.rawValue
        }
    }

    static let reminderWeekdayOptions: [(value: Int, title: String)] = [
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday"),
        (7, "Saturday"),
        (1, "Sunday")
    ]

    private let healthStore = HKHealthStore()
    private var isSchedulingWorkoutReminder = false
    private var isResolvingNotificationPermission = false
    private var isRequestingNotificationAuthorization = false

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
        if WorkoutReminderMode(rawValue: workoutReminderModeRaw) == nil {
            workoutReminderModeRaw = WorkoutReminderMode.everyXDays.rawValue
        }
        if workoutReminderMode == .weeklyWeekday && workoutReminderWeekday == 0 {
            workoutReminderWeekday = Self.defaultWorkoutReminderWeekday()
        }
        userAge = max(Self.minimumSupportedAge, min(Self.maximumSupportedAge, userAge))

        setupIntervals()
        loadWorkoutLogEntries()

        refreshNotificationPermissionState()
        refreshHealthKitAuthorizationState()

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

        if warmupDuration > 0 {
            let warmup = Interval(name: "Warm Up", duration: warmupDuration, type: .warmup)
            intervals.append(warmup)
        }

        for i in 1...numberOfIntervals {
            let highIntensity = Interval(name: "High Intensity", duration: highIntensityDuration, type: .highIntensity)
            intervals.append(highIntensity)

            if i < numberOfIntervals {
                let rest = Interval(name: "Recovery", duration: restDuration, type: .rest)
                intervals.append(rest)
            }
        }

        currentIntervalIndex = 0
        timeRemaining = intervals.first?.duration ?? 0
        intervalEndTime = nil
        updateCounts()
    }

    func updateCounts() {
        guard !intervals.isEmpty, intervals.indices.contains(currentIntervalIndex) else {
            highIntensityCount = 0
            restCount = 0
            return
        }

        let traversed = intervals.prefix(currentIntervalIndex + 1)
        highIntensityCount = traversed.filter { $0.type == .highIntensity }.count
        restCount = traversed.filter { $0.type == .rest }.count
    }

    func startTimer() {
        guard !intervals.isEmpty, intervals.indices.contains(currentIntervalIndex) else { return }

        timer?.cancel()
        timer = nil

        isRunning = true
        if workoutStartDate == nil {
            workoutStartDate = Date()
        }
        if intervalEndTime == nil {
            intervalEndTime = Date().addingTimeInterval(timeRemaining)
        }

        reconcileTimerState(now: Date(), playAlarm: false)
        guard isRunning else { return }

        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
        scheduleNextIntervalNotification()

        timer = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func stopTimer() {
        isRunning = false
        timer?.cancel()
        timer = nil
    }

    func tick() {
        guard isRunning else { return }
        reconcileTimerState(now: Date(), playAlarm: true)
    }

    func reconcileTimerState(now: Date = Date(), playAlarm: Bool) {
        guard isRunning else { return }
        guard !intervals.isEmpty, intervals.indices.contains(currentIntervalIndex) else {
            stopTimer()
            return
        }

        if intervalEndTime == nil {
            intervalEndTime = now.addingTimeInterval(timeRemaining)
        }

        guard let endTime = intervalEndTime else { return }

        if now < endTime {
            timeRemaining = max(0, endTime.timeIntervalSince(now))
            return
        }

        var cursor = currentIntervalIndex
        var intervalEndCursor = endTime
        var advanced = false

        while now >= intervalEndCursor {
            advanced = true
            if cursor + 1 >= intervals.count {
                finishWorkout()
                return
            }

            cursor += 1
            intervalEndCursor = intervalEndCursor.addingTimeInterval(intervals[cursor].duration)
        }

        currentIntervalIndex = cursor
        updateCounts()
        intervalEndTime = intervalEndCursor
        timeRemaining = max(0, intervalEndCursor.timeIntervalSince(now))

        if advanced {
            if playAlarm {
                playAlarmIfNeeded()
            }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
            scheduleNextIntervalNotification()
        }
    }

    func finishWorkout() {
        stopTimer()
        intervalEndTime = nil
        timeRemaining = 0
        showCompletionMessage = false
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])

        selectedWorkoutType = .norwegian4x4
        workoutNotesDraft = ""
        showPostWorkoutSummary = true

        if workoutRemindersEnabled {
            scheduleWorkoutReminder()
        }
        if healthKitEnabled {
            saveCompletedWorkoutToHealthKit()
            fetchVO2MaxSamples()
        }
    }

    func moveToNextInterval() {
        if currentIntervalIndex + 1 < intervals.count {
            currentIntervalIndex += 1
            timeRemaining = intervals[currentIntervalIndex].duration
            intervalEndTime = isRunning ? Date().addingTimeInterval(timeRemaining) : nil

            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
            updateCounts()
            if isRunning {
                scheduleNextIntervalNotification()
            }
        } else {
            finishWorkout()
        }
    }

    func pause() {
        if isRunning {
            timeRemaining = max(0, intervalEndTime?.timeIntervalSinceNow ?? timeRemaining)
            stopTimer()
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
        } else {
            intervalEndTime = Date().addingTimeInterval(timeRemaining)
            scheduleNextIntervalNotification()
            startTimer()
        }
    }

    func skip() {
        guard intervals.indices.contains(currentIntervalIndex) else { return }

        playAlarmIfNeeded()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["nextInterval"])
        let wasRunning = isRunning
        moveToNextInterval()

        if wasRunning, !showPostWorkoutSummary {
            startTimer()
        }
    }

    func reset() {
        stopTimer()
        setupIntervals()
        loadWorkoutLogEntries()
        isRunning = false
        showCompletionMessage = false
        showPostWorkoutSummary = false
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
        guard !isSchedulingWorkoutReminder else { return }
        isSchedulingWorkoutReminder = true
        defer { isSchedulingWorkoutReminder = false }

        guard workoutRemindersEnabled else { return }
        guard notificationPermissionState == .granted else {
            if workoutRemindersEnabled {
                workoutRemindersEnabled = false
            }
            return
        }

        cancelWorkoutReminder()
        cancelMissedWorkoutFollowUpReminder()

        switch workoutReminderMode {
        case .everyXDays:
            let days = max(1, workoutReminderDays)
            let seconds = days * 24 * 60 * 60
            scheduleNotification(
                identifier: "workoutReminder",
                title: "Time for your N4x4 session",
                body: "It’s been \(days) day(s). Ready for your next workout?",
                in: TimeInterval(seconds),
                repeats: true
            )
        case .weeklyWeekday:
            let sanitizedWeekday = (1...7).contains(workoutReminderWeekday) ? workoutReminderWeekday : Self.defaultWorkoutReminderWeekday()
            if workoutReminderWeekday != sanitizedWeekday {
                workoutReminderWeekday = sanitizedWeekday
                return
            }
            scheduleWeeklyWorkoutReminder(weekday: sanitizedWeekday)
            scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday: sanitizedWeekday)
        }
    }

    func cancelWorkoutReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["workoutReminder"])
        cancelMissedWorkoutFollowUpReminder()
    }

    private func scheduleWeeklyWorkoutReminder(weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        guard notificationPermissionState == .granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Time for your N4x4 session"
        content.body = "It’s your \(reminderWeekdayTitle(weekday)) workout day. Ready to train?"
        content.sound = .default

        var components = DateComponents()
        components.weekday = weekday
        components.hour = 9

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "workoutReminder", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling weekly reminder: \(error.localizedDescription)")
            }
        }
    }



    func saveWorkoutLogEntryAndResetSession() {
        let trimmedNotes = workoutNotesDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = WorkoutLogEntry(
            completedAt: Date(),
            workoutType: selectedWorkoutType,
            notes: trimmedNotes
        )
        workoutLogEntries.insert(entry, at: 0)
        persistWorkoutLogEntries()
        cancelMissedWorkoutFollowUpIfCompletedToday()
        showPostWorkoutSummary = false
        reset()
    }

    func closePostWorkoutSummaryWithoutSaving() {
        showPostWorkoutSummary = false
        reset()
    }

    private func loadWorkoutLogEntries() {
        guard let data = workoutLogEntriesData.data(using: .utf8) else {
            workoutLogEntries = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let decoded = try? decoder.decode([WorkoutLogEntry].self, from: data) {
            workoutLogEntries = decoded.sorted { $0.completedAt > $1.completedAt }
            return
        }

        if let legacyV2 = try? decoder.decode([LegacyWorkoutLogEntryV2].self, from: data) {
            workoutLogEntries = legacyV2
                .map {
                    WorkoutLogEntry(
                        id: $0.id ?? UUID(),
                        completedAt: $0.completedAt,
                        workoutType: WorkoutType(rawValue: $0.workoutType ?? "") ?? .norwegian4x4,
                        notes: ($0.notes ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .sorted { $0.completedAt > $1.completedAt }
            persistWorkoutLogEntries()
            return
        }

        if let legacyV1 = try? decoder.decode([LegacyWorkoutLogEntryV1].self, from: data) {
            workoutLogEntries = legacyV1
                .map {
                    WorkoutLogEntry(
                        id: $0.id ?? UUID(),
                        completedAt: $0.completedAt,
                        workoutType: .norwegian4x4,
                        notes: ""
                    )
                }
                .sorted { $0.completedAt > $1.completedAt }
            persistWorkoutLogEntries()
            return
        }

        workoutLogEntries = []
    }

    private func persistWorkoutLogEntries() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(workoutLogEntries), let json = String(data: data, encoding: .utf8) {
            workoutLogEntriesData = json
        }
    }

    private func cancelMissedWorkoutFollowUpReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.missedWorkoutFollowUpIdentifier])
    }

    private func scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday weekday: Int) {
        guard notificationPermissionState == .granted else { return }

        let calendar = Calendar.current
        let now = Date()

        guard let scheduledDate = nextOccurrence(ofWeekday: weekday, from: now),
              let followUpDate = followUpDate(from: scheduledDate),
              !hasLoggedWorkout(on: scheduledDate) else {
            return
        }

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: followUpDate)

        let content = UNMutableNotificationContent()
        content.title = "Missed yesterday? You can still do it today"
        content.body = "It’s not too late—fit in your N4x4 session today and keep the streak alive."
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: Self.missedWorkoutFollowUpIdentifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling follow-up reminder: \(error.localizedDescription)")
            }
        }
    }

    private func nextOccurrence(ofWeekday weekday: Int, from date: Date) -> Date? {
        var comps = DateComponents()
        comps.weekday = weekday
        comps.hour = 9
        comps.minute = 0

        return Calendar.current.nextDate(
            after: date,
            matching: comps,
            matchingPolicy: .nextTime,
            direction: .forward
        )
    }

    private func followUpDate(from scheduledDate: Date) -> Date? {
        let calendar = Calendar.current
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: scheduledDate) else { return nil }
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: nextDay)
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: calendar.date(from: dayComponents) ?? nextDay)
    }

    private func hasLoggedWorkout(on date: Date) -> Bool {
        workoutLogEntries.contains { Calendar.current.isDate($0.completedAt, inSameDayAs: date) }
    }

    private func cancelMissedWorkoutFollowUpIfCompletedToday() {
        let today = Date()
        guard workoutReminderMode == .weeklyWeekday,
              workoutReminderWeekday != 0,
              Calendar.current.component(.weekday, from: today) == workoutReminderWeekday else {
            return
        }

        cancelMissedWorkoutFollowUpReminder()
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
        workoutReminderMode = .everyXDays
        workoutReminderWeekday = 0

        healthKitEnabled = false
        healthAuthorizationGranted = false
        vo2DataPoints = []
        cancelWorkoutReminder()
        cancelMissedWorkoutFollowUpReminder()
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

    func ensureNotificationPermissionForToggles() {
        guard !isResolvingNotificationPermission else { return }
        isResolvingNotificationPermission = true

        refreshNotificationPermissionState { [weak self] in
            guard let self else { return }
            defer { self.isResolvingNotificationPermission = false }

            switch self.notificationPermissionState {
            case .notDetermined, .unknown:
                self.requestNotificationPermission()
            case .denied, .unavailable:
                if self.notificationsEnabled {
                    self.notificationsEnabled = false
                }
                if self.workoutRemindersEnabled {
                    self.workoutRemindersEnabled = false
                }
            case .granted:
                if self.workoutRemindersEnabled {
                    self.scheduleWorkoutReminder()
                }
            }
        }
    }

    func refreshNotificationPermissionState(completion: (() -> Void)? = nil) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                switch settings.authorizationStatus {
                case .authorized, .provisional, .ephemeral:
                    self.notificationPermissionState = .granted
                case .denied:
                    self.notificationPermissionState = .denied
                case .notDetermined:
                    self.notificationPermissionState = .notDetermined
                @unknown default:
                    self.notificationPermissionState = .unknown
                }
                completion?()
            }
        }
    }

    // Request notification permission
    func requestNotificationPermission() {
        guard !isRequestingNotificationAuthorization else { return }
        isRequestingNotificationAuthorization = true

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification permission: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                self.isRequestingNotificationAuthorization = false
                self.notificationPermissionRequested = true
                self.notificationPermissionState = granted ? .granted : .denied
                if !granted {
                    if self.notificationsEnabled {
                        self.notificationsEnabled = false
                    }
                    if self.workoutRemindersEnabled {
                        self.workoutRemindersEnabled = false
                    }
                } else if self.workoutRemindersEnabled {
                    self.scheduleWorkoutReminder()
                }
            }
        }
    }

    // Shared notification helper
    func scheduleNotification(identifier: String, title: String, body: String, in timeInterval: TimeInterval, repeats: Bool) {
        guard notificationsEnabled || workoutRemindersEnabled else { return }
        guard notificationPermissionState == .granted else { return }

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
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitEnabled = false
            healthAuthorizationGranted = false
            healthKitPermissionState = .unavailable
            return
        }

        guard let vo2Type = HKObjectType.quantityType(forIdentifier: .vo2Max) else {
            healthKitPermissionState = .unavailable
            return
        }

        let readTypes: Set<HKObjectType> = [vo2Type, HKObjectType.workoutType()]
        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType()]

        healthStore.requestAuthorization(toShare: writeTypes, read: readTypes) { success, error in
            DispatchQueue.main.async {
                self.healthAuthorizationGranted = success
                self.refreshHealthKitAuthorizationState()
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

    func refreshHealthKitAuthorizationState() {
        guard HKHealthStore.isHealthDataAvailable() else {
            healthKitPermissionState = .unavailable
            healthAuthorizationGranted = false
            return
        }

        let workoutStatus = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        switch workoutStatus {
        case .sharingAuthorized:
            healthKitPermissionState = .granted
            healthAuthorizationGranted = true
        case .sharingDenied:
            healthKitPermissionState = .denied
            healthAuthorizationGranted = false
            healthKitEnabled = false
        case .notDetermined:
            healthKitPermissionState = .notDetermined
            healthAuthorizationGranted = false
        @unknown default:
            healthKitPermissionState = .unknown
            healthAuthorizationGranted = false
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

        let config = HKWorkoutConfiguration()
        config.activityType = .highIntensityIntervalTraining
        config.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: healthStore, configuration: config, device: .local())

        builder.beginCollection(withStart: startDate) { _, beginError in
            if let beginError = beginError {
                print("Workout beginCollection error: \(beginError.localizedDescription)")
                return
            }

            builder.endCollection(withEnd: endDate) { _, endError in
                if let endError = endError {
                    print("Workout endCollection error: \(endError.localizedDescription)")
                    return
                }

                builder.finishWorkout { _, finishError in
                    if let finishError = finishError {
                        print("Workout finish error: \(finishError.localizedDescription)")
                    }
                }
            }
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }

    func reminderWeekdayTitle(_ weekday: Int) -> String {
        Self.reminderWeekdayOptions.first(where: { $0.value == weekday })?.title ?? "Not set"
    }

    static func defaultWorkoutReminderWeekday() -> Int {
        Calendar.current.component(.weekday, from: Date())
    }

    func totalWorkoutDuration() -> TimeInterval {
        intervals.reduce(0) { $0 + $1.duration }
    }
}
