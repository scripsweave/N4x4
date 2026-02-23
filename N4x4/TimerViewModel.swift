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
    case weeklyWeekday

    var id: String { rawValue }

    var title: String {
        switch self {
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

    var weekOfYear: Int {
        Calendar.current.component(.weekOfYear, from: completedAt)
    }

    var year: Int {
        Calendar.current.component(.year, from: completedAt)
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
    private static let missedWorkoutFollowUpIdentifierPrefix = "workoutReminderFollowup_"
    
    private func missedWorkoutFollowUpIdentifier(for weekday: Int) -> String {
        return Self.missedWorkoutFollowUpIdentifierPrefix + "\(weekday)"
    }

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

    // Streak tracking
    @AppStorage("currentStreak") var currentStreak: Int = 0
    @AppStorage("longestStreak") var longestStreak: Int = 0
    @AppStorage("hasMadeCommitment") var hasMadeCommitment: Bool = false
    @AppStorage("committedWeeks") var committedWeeks: Int = 5  // Default 5-week commitment

    // Reminder notifications - now supports multiple days per week
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
            if workoutRemindersEnabled {
                scheduleWorkoutReminder()
            }
        }
    }
    @AppStorage("workoutReminderMode") private var workoutReminderModeRaw: String = WorkoutReminderMode.weeklyWeekday.rawValue {
        didSet {
            let sanitized = WorkoutReminderMode(rawValue: workoutReminderModeRaw)?.rawValue ?? WorkoutReminderMode.weeklyWeekday.rawValue
            if sanitized != workoutReminderModeRaw {
                workoutReminderModeRaw = sanitized
                return
            }
            guard oldValue != workoutReminderModeRaw else { return }

            if workoutRemindersEnabled {
                scheduleWorkoutReminder()
            }
        }
    }
    // Store multiple weekdays as comma-separated string (e.g., "1,3,5" for Mon,Wed,Fri)
    @AppStorage("workoutReminderWeekdays") var workoutReminderWeekdays: String = "" {
        didSet {
            guard oldValue != workoutReminderWeekdays else { return }
            // Skip sync if this change came from our own @Published setter (infinite loop prevention)
            guard !isSyncingFromPublished else { return }
            
            // Sync @Published property when AppStorage changes externally
            if workoutReminderWeekdays.isEmpty {
                selectedWeekdaysList = []
            } else {
                selectedWeekdaysList = workoutReminderWeekdays
                    .split(separator: ",")
                    .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    .filter { (1...7).contains($0) }
            }
            if workoutRemindersEnabled, workoutReminderMode == .weeklyWeekday {
                scheduleWorkoutReminder()
            }
        }
    }
    
    // Flag to prevent circular sync between @Published and @AppStorage
    private var isSyncingFromPublished = false

    // Legacy support for single weekday
    @AppStorage("workoutReminderWeekday") var workoutReminderWeekday: Int = 0 {
        didSet {
            // Migrate legacy single weekday to new format
            if oldValue > 0 && workoutReminderWeekdays.isEmpty {
                workoutReminderWeekdays = String(oldValue)
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
        get { WorkoutReminderMode(rawValue: workoutReminderModeRaw) ?? .weeklyWeekday }
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

    // MARK: - Multi-day Reminder Helpers

    // @Published property for stable in-memory state (synced with AppStorage)
    @Published var selectedWeekdaysList: [Int] = [] {
        didSet {
            // Sync to AppStorage when value changes (via flag to prevent circular sync)
            isSyncingFromPublished = true
            let sorted = selectedWeekdaysList.sorted()
            workoutReminderWeekdays = sorted.map { String($0) }.joined(separator: ",")
            isSyncingFromPublished = false
        }
    }

    var selectedWeekdays: [Int] {
        get { selectedWeekdaysList }
        set { selectedWeekdaysList = newValue }
    }

    func toggleWeekday(_ weekday: Int) {
        var days = selectedWeekdaysList
        if days.contains(weekday) {
            days.removeAll { $0 == weekday }
        } else {
            days.append(weekday)
        }
        selectedWeekdaysList = days
    }
    
    /// Force sync selected days to AppStorage and schedule reminders
    /// Used by onboarding to ensure reminders are scheduled after user selects days
    func enableRemindersWithSelectedDays() {
        workoutReminderMode = .weeklyWeekday
        // Force sync to AppStorage immediately
        isSyncingFromPublished = true
        let sorted = selectedWeekdaysList.sorted()
        workoutReminderWeekdays = sorted.map { String($0) }.joined(separator: ",")
        isSyncingFromPublished = false
        // Now enable reminders (this will trigger scheduling)
        workoutRemindersEnabled = true
    }

    func isWeekdaySelected(_ weekday: Int) -> Bool {
        selectedWeekdaysList.contains(weekday)
    }

    // MARK: - Streak Calculation

    var currentWeekStreak: Int {
        calculateCurrentStreak()
    }

    private func calculateCurrentStreak() -> Int {
        guard !workoutLogEntries.isEmpty else { return 0 }

        let calendar = Calendar.current
        let now = Date()
        var streak = 0
        var currentWeek = calendar.component(.weekOfYear, from: now)
        var currentYear = calendar.component(.year, from: now)

        // Get unique weeks from workout entries using a Hashable key
        struct WeekKey: Hashable { let year: Int; let week: Int }
        let uniqueWeeks: Set<WeekKey> = Set(workoutLogEntries.map { WeekKey(year: $0.year, week: $0.weekOfYear) })
        let sortedWeeks = uniqueWeeks.sorted { lhs, rhs in
            if lhs.year != rhs.year { return lhs.year > rhs.year }
            return lhs.week > rhs.week
        }

        // Check from current week backwards
        for key in sortedWeeks {
            let year = key.year
            let week = key.week

            if year == currentYear && week == currentWeek {
                streak += 1
                currentWeek -= 1
                if currentWeek < 1 {
                    currentYear -= 1
                    let lastWeek = calendar.component(.weekOfYear, from: calendar.date(from: DateComponents(year: currentYear, month: 12, day: 28))!)
                    currentWeek = lastWeek
                }
            } else if year == currentYear && week == currentWeek - 1 {
                streak += 1
                currentWeek = week - 1
                if currentWeek < 1 {
                    currentYear -= 1
                    currentWeek = 52
                }
            } else {
                break
            }
        }

        return streak
    }

    func updateStreakOnWorkoutComplete() {
        let newStreak = currentWeekStreak
        if newStreak > currentStreak {
            currentStreak = newStreak
        }
        if currentStreak > longestStreak {
            longestStreak = currentStreak
        }
    }

    // MARK: - Success Messages

    static let successMessages: [String] = [
        "Crushing it, Viking! 🪓",
        "Another workout, another victory! ⚔️",
        "Your VO2 max is thanking you! 💪",
        "Stronger than yesterday! 🔥",
        "Viking tradition: never skip training! 🛡️",
        "Epic workout complete! 🏆",
        "You're becoming unstoppable! ⭐",
        "The forge grows stronger! 🔨",
        "Discipline is your superpower! 🎯",
        "One workout at a time! 👊"
    ]

    var randomSuccessMessage: String {
        Self.successMessages.randomElement() ?? "Great job, Viking!"
    }

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
        // Initialize selectedWeekdaysList from AppStorage
        if !workoutReminderWeekdays.isEmpty {
            selectedWeekdaysList = workoutReminderWeekdays
                .split(separator: ",")
                .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                .filter { (1...7).contains($0) }
        }
        
        // Reschedule reminders on app launch to handle missed days
        rescheduleRemindersOnAppLaunch()
        
        if numberOfIntervals < 1 {
            numberOfIntervals = 4 // Default value
        }
        if workoutReminderDays < 1 {
            workoutReminderDays = 7
        }
        if workoutReminderModeRaw.isEmpty {
            workoutReminderModeRaw = WorkoutReminderMode.weeklyWeekday.rawValue
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
        
        // Update streak
        updateStreakOnWorkoutComplete()

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

    /// Reschedules reminders on app launch to handle missed workout days
    /// This ensures follow-ups are resent if user didn't open app for a while
    func rescheduleRemindersOnAppLaunch() {
        guard workoutRemindersEnabled, workoutReminderMode == .weeklyWeekday else { return }
        
        let weekdays = selectedWeekdaysList
        guard !weekdays.isEmpty else { return }
        
        // For each selected weekday, check if we missed the workout window and reschedule follow-ups
        for weekday in weekdays {
            // Cancel existing follow-ups for this weekday
            cancelMissedWorkoutFollowUpReminder(for: weekday)
            
            // Reschedule follow-ups (this will check if workout was logged and handle accordingly)
            scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday: weekday)
        }
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

        // Only weekly weekday mode is supported
        let weekdays = selectedWeekdays
        if weekdays.isEmpty {
            // Default to today if no days selected
            let today = Calendar.current.component(.weekday, from: Date())
            scheduleWeeklyWorkoutReminder(weekday: today)
            scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday: today)
        } else {
            // Schedule for each selected weekday
            for weekday in weekdays {
                scheduleWeeklyWorkoutReminder(weekday: weekday)
                scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday: weekday)
            }
        }
    }

    func cancelWorkoutReminder() {
        cancelAllWeeklyReminders()
        cancelMissedWorkoutFollowUpReminder()
    }

    private func scheduleWeeklyWorkoutReminder(weekday: Int) {
        guard (1...7).contains(weekday) else { return }
        guard notificationPermissionState == .granted else { return }

        let content = UNMutableNotificationContent()
        // Fun Viking messages for night-before reminder
        let nightMessages: [(String, String)] = [
            ("Tomorrow is workout day, Viking! 🪓", "You committed to train tomorrow. Ready to crush it?"),
            ("Your Viking workout awaits tomorrow", "Don't let your training slip - N4x4 is ready when you are."),
            ("Heads up, Viking! 📢", "You have a workout scheduled for tomorrow. Let's go!"),
            ("Training day tomorrow! ⚔️", "Your body is waiting. Tomorrow we ride!"),
            ("Reminder: Viking duty calls tomorrow", "You've got this. Tomorrow's workout is calling your name.")
        ]
        let msg = nightMessages.randomElement()!
        content.title = msg.0
        content.body = msg.1
        content.sound = .default

        // Schedule for 8pm the day BEFORE the workout day
        var components = DateComponents()
        components.weekday = weekday
        components.hour = 20  // 8pm
        components.minute = 0
        
        // For repeats, we need to schedule for day-before so it fires correctly each week
        // Actually, for repeating weekly, we set the weekday and it repeats - but we want day-before
        // Let's adjust: schedule for (weekday - 1) at 8pm to be the day before
        let dayBeforeWeekday = weekday == 1 ? 7 : weekday - 1  // Sunday -> Saturday
        components.weekday = dayBeforeWeekday

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        // Use unique identifier per weekday
        let request = UNNotificationRequest(identifier: "workoutReminder_\(weekday)", content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling weekly reminder: \(error.localizedDescription)")
            }
        }
    }
    
    private func cancelAllWeeklyReminders() {
        // Cancel all possible weekday reminders
        for weekday in 1...7 {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["workoutReminder_\(weekday)"])
        }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["workoutReminder"])
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

    private func cancelMissedWorkoutFollowUpReminder(for weekday: Int? = nil) {
        if let weekday = weekday {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [missedWorkoutFollowUpIdentifier(for: weekday)])
        } else {
            // Cancel all weekday-specific follow-ups
            for wd in 1...7 {
                UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [missedWorkoutFollowUpIdentifier(for: wd)])
            }
        }
    }

    private func scheduleMissedWorkoutFollowUpReminder(forScheduledWeekday weekday: Int) {
        guard notificationPermissionState == .granted else { return }

        let calendar = Calendar.current
        let now = Date()

        // Find the next scheduled workout day
        guard let scheduledDate = nextOccurrence(ofWeekday: weekday, from: now) else {
            return
        }
        
        // Check if workout already logged on that day
        if hasLoggedWorkout(on: scheduledDate) {
            // Workout was logged, cancel any pending follow-up
            cancelMissedWorkoutFollowUpReminder(for: weekday)
            return
        }

        // Determine when to send follow-up: next day at 8am
        guard let followUpDate = followUpDate(from: scheduledDate) else {
            return
        }
        
        // Only schedule if follow-up is in the future
        guard followUpDate > now else {
            // Follow-up time has passed, schedule for tomorrow
            scheduleRecurringFollowUp(from: now, weekday: weekday)
            return
        }

        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: followUpDate)

        // Random morning-of message
        let morningMessages: [(String, String)] = [
            ("Rise and grind, Viking! ☀️", "Your workout is waiting. There's no time like the present!"),
            ("Morning workout energy! ⚡", "The best time to train is now. Let's go!"),
            ("Your Viking workout awaits", "Today is your training day. Don't break the streak!"),
            ("Time to conquer, Viking! 🛡️", "Your body is ready. Are you?"),
            ("No more waiting - it's go time! 🎯", "You've committed to train today. Let's do this!")
        ]
        let msg = morningMessages.randomElement()!
        let content = UNMutableNotificationContent()
        content.title = msg.0
        content.body = msg.1
        content.sound = .default

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let identifier = missedWorkoutFollowUpIdentifier(for: weekday)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error scheduling follow-up reminder: \(error.localizedDescription)")
            }
        }
        
        // Also schedule a recursive follow-up for every day until workout is logged OR next scheduled reminder
        scheduleRecurringFollowUp(from: now, weekday: weekday)
    }
    
    private func scheduleRecurringFollowUp(from startDate: Date, weekday: Int) {
        guard notificationPermissionState == .granted else { return }
        
        let calendar = Calendar.current
        
        // Find next scheduled workout day
        guard let scheduledDate = nextOccurrence(ofWeekday: weekday, from: startDate) else {
            return
        }
        
        // If workout already logged, stop
        if hasLoggedWorkout(on: scheduledDate) {
            return
        }
        
        // Schedule daily follow-ups starting from tomorrow until the day before next scheduled workout
        var currentDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        
        // Find when the next scheduled reminder will fire (day before scheduled workout)
        let dayBeforeScheduled = calendar.date(byAdding: .day, value: -1, to: scheduledDate) ?? scheduledDate
        
        // Keep scheduling until we reach the day before the next scheduled workout
        while currentDate <= dayBeforeScheduled {
            let components = calendar.dateComponents([.year, .month, .day], from: currentDate)
            var notificationComponents = components
            notificationComponents.hour = 10  // 10am follow-up
            notificationComponents.minute = 0
            
            // Random encouraging message for daily follow-ups
            let nagMessages: [(String, String)] = [
                ("You missed one day, Viking. No biggie. 🪓", "It's never too late. There's no time like the present."),
                ("Yesterday slipped by - no worries! ⏳", "Your streak isn't dead. Train today and come back stronger!"),
                ("Vikings don't quit - they adapt! ⚔️", "One missed day doesn't define you. Let's get back on the horse!"),
                ("Hey Viking, you okay? 💪", "We miss your energy. Today's a fresh start - let's go!"),
                ("Don't let one day become two! 🚨", "Your future self will thank you. Time to train!"),
                ("The storm doesn't stop the Viking! 🌩️", "Life happens. But your training? That's up to you."),
                ("Vikings rise, even after a fall! 🆙", "One workout is all it takes to get back on track.")
            ]
            let msg = nagMessages.randomElement()!
            let content = UNMutableNotificationContent()
            content.title = msg.0
            content.body = msg.1
            content.sound = .default
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: notificationComponents, repeats: false)
            let identifier = "\(missedWorkoutFollowUpIdentifier(for: weekday))_daily_\(calendar.component(.day, from: currentDate))"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
            UNUserNotificationCenter.current().add(request) { error in
                if let error = error {
                    print("Error scheduling daily follow-up: \(error.localizedDescription)")
                }
            }
            
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate) ?? currentDate
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
        // Follow-up fires at 8am on the workout day itself (since reminder fires night before)
        let calendar = Calendar.current
        let dayComponents = calendar.dateComponents([.year, .month, .day], from: scheduledDate)
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: calendar.date(from: dayComponents) ?? scheduledDate)
    }

    private func hasLoggedWorkout(on date: Date) -> Bool {
        workoutLogEntries.contains { Calendar.current.isDate($0.completedAt, inSameDayAs: date) }
    }

    private func cancelMissedWorkoutFollowUpIfCompletedToday() {
        let today = Date()
        let todayWeekday = Calendar.current.component(.weekday, from: today)
        
        guard workoutReminderMode == .weeklyWeekday else { return }
        
        // Cancel follow-ups for any weekday matching today
        for weekday in selectedWeekdaysList {
            if weekday == todayWeekday {
                cancelMissedWorkoutFollowUpReminder(for: weekday)
            }
        }
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
        workoutReminderMode = .weeklyWeekday
        workoutReminderWeekdays = ""
        
        // Reset streaks but keep commitment
        currentStreak = 0
        longestStreak = 0

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

