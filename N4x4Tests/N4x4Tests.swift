import XCTest
import UserNotifications
@testable import N4x4

private final class TestIntervalNotificationCenter: IntervalNotificationCenter {
    var pending: [String: UNNotificationRequest] = [:]
    var delivered: Set<String> = []
    var holdNextAdd = false
    var onAddStarted: (() -> Void)?
    var addContinuation: CheckedContinuation<Void, Never>?

    func add(_ request: UNNotificationRequest) async throws {
        if holdNextAdd {
            holdNextAdd = false
            await withCheckedContinuation { continuation in
                addContinuation = continuation
                onAddStarted?()
            }
        }
        pending[request.identifier] = request
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        for identifier in identifiers { pending.removeValue(forKey: identifier) }
    }

    func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
        delivered.subtract(identifiers)
    }
}

private final class TestWorkoutActivity: WorkoutLiveActivityHandle {
    let id = UUID().uuidString
    var events: [String] = []
    var holdNextUpdate = false
    var onUpdateStarted: (() -> Void)?
    var updateContinuation: CheckedContinuation<Void, Never>?

    func updateWorkout(_ state: N4x4LiveActivityAttributes.ContentState) async {
        if holdNextUpdate {
            holdNextUpdate = false
            await withCheckedContinuation { continuation in
                updateContinuation = continuation
                onUpdateStarted?()
            }
        }
        events.append(state.isRunning ? "running" : "paused")
    }

    func endWorkout() async { events.append("end") }
}

private final class TestWorkoutActivityProvider: WorkoutLiveActivityProvider {
    var stored: [TestWorkoutActivity] = []
    var activities: [any WorkoutLiveActivityHandle] { stored }
    var areActivitiesEnabled = true

    func request(start: Date, state: N4x4LiveActivityAttributes.ContentState) throws -> any WorkoutLiveActivityHandle {
        let activity = TestWorkoutActivity()
        stored.append(activity)
        return activity
    }
}

final class N4x4Tests: XCTestCase {

    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.standard
        [
            "numberOfIntervals",
            "warmupDuration",
            "highIntensityDuration",
            "restDuration",
            "alarmEnabled",
            "preventSleep",
            "userAge",
            "notificationsEnabled",
            "notificationPermissionRequested",
            "workoutRemindersEnabled",
            "workoutReminderDays",
            "workoutReminderMode",
            "workoutReminderWeekday",
            "healthKitEnabled",
            "healthKitUserOptedOut",
            "hasCompletedOnboarding",
            "workoutLogEntriesData",
            "unitPreference",
            "preferredModalityRaw",
            "defaultWorkoutTypeRaw",
            "nightBeforeReminderEnabled",
            "morningOfReminderEnabled",
            "comebackNudgesEnabled",
            "reminderFamilyFlagsSynced",
            "workoutReminderWeekdays",
            "appleSensorHREnabled",
            "hrSourcePriorityRaw",
            "cooldownEnabled", "audioModeRaw", "hapticsEnabled", "shownMilestonesData",
            "hasRequestedAppReview", "liveActivitiesEnabled"
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    @MainActor
    private func effectsViewModel(center: TestIntervalNotificationCenter,
                                  activities: TestWorkoutActivityProvider) -> TimerViewModel {
        UserDefaults.standard.set(false, forKey: "healthKitEnabled")
        UserDefaults.standard.set(true, forKey: "healthKitUserOptedOut")
        UserDefaults.standard.set(false, forKey: "workoutRemindersEnabled")
        UserDefaults.standard.set(true, forKey: "notificationsEnabled")
        let vm = TimerViewModel(intervalNotificationCenter: center, liveActivityProvider: activities)
        vm.audioMode = .silent
        vm.hapticsEnabled = false
        vm.warmupDuration = 600
        vm.numberOfIntervals = 2
        vm.notificationPermissionState = .granted
        vm.notificationsEnabled = true
        vm.workoutStartDate = Date()
        vm.isRunning = true
        vm.intervalEndTime = Date().addingTimeInterval(600)
        return vm
    }

    @MainActor
    func testEndingDuringNotificationAddDrainsOldCueBeforeNewWorkout() async throws {
        let center = TestIntervalNotificationCenter()
        let activities = TestWorkoutActivityProvider()
        let vm = effectsViewModel(center: center, activities: activities)
        let addStarted = expectation(description: "Old workout notification add is in flight")
        center.holdNextAdd = true
        center.onAddStarted = { addStarted.fulfill() }
        vm.scheduleNextIntervalNotification()
        await fulfillment(of: [addStarted], timeout: 3)

        vm.reset()
        vm.workoutStartDate = Date()
        vm.isRunning = true
        vm.currentIntervalIndex = 1
        // The real authorization refresh may have completed during the await;
        // this fake scheduler deliberately tests an authorized notification flow.
        vm.notificationPermissionState = .granted
        vm.notificationsEnabled = true
        vm.scheduleNextIntervalNotification()
        center.addContinuation?.resume()
        await vm.intervalNotificationTask?.value

        XCTAssertEqual(center.pending.count, 1)
        XCTAssertTrue(center.pending["nextInterval"]?.content.body.contains("Recovery") == true,
                      "Cleanup from the old workout must not remove the new workout's cue")
        vm.reset()
        await vm.intervalNotificationTask?.value
        XCTAssertTrue(center.pending.isEmpty)
    }

    @MainActor
    func testPauseResetAndCompletionRemovePendingAndDeliveredIntervalCuesOnly() async throws {
        for action in ["pause", "reset", "complete"] {
            let center = TestIntervalNotificationCenter()
            let vm = effectsViewModel(center: center, activities: TestWorkoutActivityProvider())
            let reminder = UNNotificationRequest(identifier: "workoutReminder_2",
                                                 content: UNMutableNotificationContent(), trigger: nil)
            center.pending[reminder.identifier] = reminder
            center.delivered = ["nextInterval", reminder.identifier, "birthdayNudge_0802"]
            vm.scheduleNextIntervalNotification()
            await vm.intervalNotificationTask?.value
            XCTAssertNotNil(center.pending["nextInterval"])

            switch action {
            case "pause": vm.pause()
            case "reset": vm.reset()
            default: vm.finishWorkout()
            }
            // A delayed caller cannot queue cues after a workout stops.
            vm.scheduleNextIntervalNotification()
            await vm.intervalNotificationTask?.value
            XCTAssertEqual(Set(center.pending.keys), [reminder.identifier], action)
            XCTAssertEqual(center.delivered, [reminder.identifier, "birthdayNudge_0802"], action)
            vm.reset()
        }
    }

    @MainActor
    func testLaunchCleansOrphanActivityWithoutEndingNewWorkout() async {
        let center = TestIntervalNotificationCenter()
        let activities = TestWorkoutActivityProvider()
        let orphan = TestWorkoutActivity()
        activities.stored = [orphan]
        let vm = effectsViewModel(center: center, activities: activities)
        vm.startLiveActivity()
        let newActivity = activities.stored.last!
        await vm.liveActivityTask?.value
        XCTAssertTrue(orphan.events.contains("end"))
        XCTAssertFalse(newActivity.events.contains("end"), "Launch cleanup must capture activities before yielding")
        vm.reset()
        await vm.liveActivityTask?.value
        XCTAssertEqual(newActivity.events.last, "end")
    }

    @MainActor
    func testEndingWaitsForInFlightActivityUpdateAndAlsoEndsOrphans() async {
        let activities = TestWorkoutActivityProvider()
        let vm = effectsViewModel(center: TestIntervalNotificationCenter(), activities: activities)
        await vm.liveActivityTask?.value
        vm.startLiveActivity()
        let live = activities.stored.last!
        let updateStarted = expectation(description: "Activity update suspended")
        live.holdNextUpdate = true
        live.onUpdateStarted = { updateStarted.fulfill() }
        vm.updateLiveActivity(isRunning: true)
        await fulfillment(of: [updateStarted], timeout: 3)
        let orphan = TestWorkoutActivity()
        activities.stored.append(orphan)

        vm.reset()
        vm.updateLiveActivity(isRunning: true)
        vm.startLiveActivity()
        live.updateContinuation?.resume()
        await vm.liveActivityTask?.value
        XCTAssertEqual(live.events, ["running", "end"])
        XCTAssertEqual(orphan.events, ["end"])
        XCTAssertEqual(activities.stored.count, 2, "Reset cannot restart a Live Activity")
    }

    @MainActor
    func testCompletionEndsActivityAndCannotRestartUntilReviewIsDismissed() async {
        let activities = TestWorkoutActivityProvider()
        let vm = effectsViewModel(center: TestIntervalNotificationCenter(), activities: activities)
        await vm.liveActivityTask?.value
        vm.startLiveActivity()
        let live = activities.stored.last!
        vm.finishWorkout()
        vm.startTimer()
        await vm.liveActivityTask?.value
        XCTAssertEqual(live.events.last, "end")
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(activities.stored.count, 1)
        XCTAssertNotNil(vm.completedWorkoutEntryID)
        vm.reset()
    }

    @MainActor
    func testDisablingIntervalCuesWhileAddIsInFlightRemovesThem() async {
        let center = TestIntervalNotificationCenter()
        let vm = effectsViewModel(center: center, activities: TestWorkoutActivityProvider())
        let addStarted = expectation(description: "Notification add suspended")
        center.holdNextAdd = true
        center.onAddStarted = { addStarted.fulfill() }
        vm.scheduleNextIntervalNotification()
        await fulfillment(of: [addStarted], timeout: 3)
        vm.notificationsEnabled = false
        center.addContinuation?.resume()
        await vm.intervalNotificationTask?.value
        XCTAssertTrue(center.pending.isEmpty)
        vm.reset()
    }

    @MainActor
    func testLaunchRemovesOldIntervalCuesAndRetainsReminders() async {
        let center = TestIntervalNotificationCenter()
        for id in ["nextInterval", "workoutReminder_2", "birthdayNudge_0802"] {
            center.pending[id] = UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil)
            center.delivered.insert(id)
        }
        let vm = TimerViewModel(intervalNotificationCenter: center, liveActivityProvider: TestWorkoutActivityProvider())
        await vm.intervalNotificationTask?.value
        XCTAssertEqual(Set(center.pending.keys), ["workoutReminder_2", "birthdayNudge_0802"])
        XCTAssertEqual(center.delivered, ["workoutReminder_2", "birthdayNudge_0802"])
    }

    func testSetupIntervalsIncludesWarmupAndCorrectPattern() {
        let vm = TimerViewModel()
        vm.cooldownEnabled = false   // isolate the warmup + work/recovery pattern
        vm.numberOfIntervals = 3
        vm.warmupDuration = 120
        vm.highIntensityDuration = 240
        vm.restDuration = 180
        vm.setupIntervals()

        XCTAssertEqual(vm.intervals.count, 6)
        XCTAssertEqual(vm.intervals[0].type, .warmup)
        XCTAssertEqual(vm.intervals[1].type, .highIntensity)
        XCTAssertEqual(vm.intervals[2].type, .rest)
        XCTAssertEqual(vm.intervals[2].name, "Recovery")
        XCTAssertEqual(vm.intervals[3].type, .highIntensity)
        XCTAssertEqual(vm.intervals[4].type, .rest)
        XCTAssertEqual(vm.intervals[4].name, "Recovery")
        XCTAssertEqual(vm.intervals[5].type, .highIntensity)
    }

    func testSetupIntervalsAppendsCooldownWhenEnabled() {
        let vm = TimerViewModel()
        vm.cooldownEnabled = true
        vm.numberOfIntervals = 2
        vm.warmupDuration = 120
        vm.highIntensityDuration = 240
        vm.restDuration = 180
        vm.setupIntervals()

        // warmup + [HI, rest, HI] + cooldown
        XCTAssertEqual(vm.intervals.count, 5)
        XCTAssertEqual(vm.intervals.last?.type, .cooldown)
    }

    func testCatchUpAdvancesAcrossMultipleIntervals() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 2
        vm.warmupDuration = 10
        vm.highIntensityDuration = 10
        vm.restDuration = 10
        vm.setupIntervals()

        vm.isRunning = true
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 10

        let start = Date()
        vm.intervalEndTime = start.addingTimeInterval(10)

        vm.reconcileTimerState(now: start.addingTimeInterval(25), playAlarm: false)

        XCTAssertEqual(vm.currentIntervalIndex, 2, "Expected to advance warmup + first high interval")
        XCTAssertGreaterThan(vm.timeRemaining, 0)
        XCTAssertLessThanOrEqual(vm.timeRemaining, 10)
        XCTAssertTrue(vm.isRunning)
    }

    func testCatchUpCompletesWorkoutWhenFarPastEnd() {
        let vm = TimerViewModel()
        vm.cooldownEnabled = false   // completion is being tested, not the cooldown tail
        vm.numberOfIntervals = 1
        vm.warmupDuration = 5
        vm.highIntensityDuration = 5
        vm.setupIntervals()

        vm.isRunning = true
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 5

        let start = Date()
        vm.intervalEndTime = start.addingTimeInterval(5)

        vm.reconcileTimerState(now: start.addingTimeInterval(20), playAlarm: false)

        XCTAssertTrue(vm.showPostWorkoutSummary)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.timeRemaining, 0)
        XCTAssertEqual(vm.workoutLogEntries.count, 1, "Timer catch-up must autosave before review")
    }

    func testPauseAndResumeMaintainsRunningState() {
        let vm = TimerViewModel()
        vm.setupIntervals()

        vm.startTimer()
        XCTAssertTrue(vm.isRunning)

        vm.pause()
        XCTAssertFalse(vm.isRunning)

        vm.pause()
        XCTAssertTrue(vm.isRunning)
    }

    func testSkipAdvancesCurrentInterval() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 2
        vm.warmupDuration = 10
        vm.setupIntervals()
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 10

        vm.skip()

        XCTAssertEqual(vm.currentIntervalIndex, 1)
    }

    func testSkipWhilePausedDoesNotStartElapsedCountdown() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 2
        vm.warmupDuration = 10
        vm.highIntensityDuration = 10
        vm.setupIntervals()
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 10
        vm.isRunning = false

        vm.skip()

        XCTAssertEqual(vm.currentIntervalIndex, 1)
        XCTAssertNil(vm.intervalEndTime)
        XCTAssertFalse(vm.isRunning)
    }

    func testSkippingFinalIntervalWhileRunningEndsWorkoutWithoutRestartingTimer() {
        let vm = TimerViewModel()
        vm.cooldownEnabled = false   // so the high-intensity interval is the final one
        vm.numberOfIntervals = 1
        vm.warmupDuration = 0
        vm.highIntensityDuration = 10
        vm.setupIntervals()
        vm.currentIntervalIndex = 0
        vm.timeRemaining = 2
        vm.isRunning = true

        vm.skip()

        XCTAssertTrue(vm.showPostWorkoutSummary)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNil(vm.intervalEndTime)
    }

    func testScheduleWorkoutReminderDisabledWithoutNotificationPermission() {
        let vm = TimerViewModel()
        vm.notificationPermissionState = .denied
        vm.workoutRemindersEnabled = true
        vm.scheduleWorkoutReminder()

        XCTAssertFalse(vm.workoutRemindersEnabled)
    }

    func testHealthKitSaveGuardWhenUnauthorized() {
        let vm = TimerViewModel()
        vm.healthKitEnabled = true
        vm.healthAuthorizationGranted = false

        vm.saveCompletedWorkoutToHealthKit()

        XCTAssertFalse(vm.healthAuthorizationGranted)
    }

    func testDeleteWorkoutLogEntryRemovesEntryAndPersists() {
        let vm = TimerViewModel()
        let id = UUID()
        vm.workoutLogEntries = [WorkoutLogEntry(id: id, workoutType: .run, notes: "test")]

        vm.deleteWorkoutLogEntry(id: id)

        XCTAssertTrue(vm.workoutLogEntries.isEmpty)
        let reloaded = TimerViewModel()
        XCTAssertTrue(reloaded.workoutLogEntries.isEmpty)
    }

    func testDeleteUnknownWorkoutIsNoOp() {
        let vm = TimerViewModel()
        let entry = WorkoutLogEntry(workoutType: .run, notes: "test")
        vm.workoutLogEntries = [entry]

        vm.deleteWorkoutLogEntry(id: UUID())

        XCTAssertEqual(vm.workoutLogEntries, [entry])
    }

    func testOnboardingFlowMovesForwardAndBackWithinBounds() {
        let flow = OnboardingFlowViewModel()

        XCTAssertEqual(flow.currentStep, .welcome)

        flow.next()
        XCTAssertEqual(flow.currentStep, .basics)

        flow.back()
        XCTAssertEqual(flow.currentStep, .welcome)

        flow.back()
        XCTAssertEqual(flow.currentStep, .welcome)
    }

    func testOnboardingFlowStopsAtLastStep() {
        let flow = OnboardingFlowViewModel()

        OnboardingFlowViewModel.Step.allCases.forEach { _ in
            flow.next()
        }

        XCTAssertEqual(flow.currentStep, .launch)
        XCTAssertTrue(flow.isLastStep)
    }

    func testOnboardingFlowIncludesReminderDayStep() {
        let flow = OnboardingFlowViewModel()

        flow.next() // basics
        flow.next() // modality
        flow.next() // age
        flow.next() // vo2Goal
        flow.next() // reminderDay

        XCTAssertEqual(flow.currentStep, .reminderDay)
    }

    func testWorkoutReminderModeDefaultsToWeeklyWeekday() {
        let vm = TimerViewModel()
        XCTAssertEqual(vm.workoutReminderMode, .weeklyWeekday)
    }

    func testSelectingWeekdaysSyncsAndStaysValid() {
        // The reminder model is multi-day now (selectedWeekdaysList); the legacy
        // single `workoutReminderWeekday` is only a migration shim.
        let vm = TimerViewModel()
        vm.selectedWeekdaysList = [2, 5, 7]

        XCTAssertEqual(vm.selectedWeekdaysList.sorted(), [2, 5, 7])
        XCTAssertTrue(vm.selectedWeekdaysList.allSatisfy { (1...7).contains($0) })
        XCTAssertEqual(vm.workoutReminderMode, .weeklyWeekday)
    }

    func testReminderWeekdayTitlesIncludeMondayAndSunday() {
        let vm = TimerViewModel()

        XCTAssertEqual(vm.reminderWeekdayTitle(2), "Monday")
        XCTAssertEqual(vm.reminderWeekdayTitle(1), "Sunday")
    }

    func testSavingWorkoutLogEntryPersistsAndResets() {
        let vm = TimerViewModel()
        vm.finishWorkout()
        let savedID = vm.workoutLogEntries.first?.id
        vm.selectedWorkoutType = .cycle
        vm.workoutNotesDraft = "Felt strong"
        vm.showPostWorkoutSummary = true

        vm.completeWorkoutReview()

        XCTAssertEqual(vm.workoutLogEntries.count, 1)
        XCTAssertEqual(vm.workoutLogEntries.first?.id, savedID)
        XCTAssertEqual(vm.workoutLogEntries.first?.workoutType, .cycle)
        XCTAssertEqual(vm.workoutLogEntries.first?.notes, "Felt strong")
        XCTAssertFalse(vm.showPostWorkoutSummary)
    }

    func testWorkoutTypeIncludesOtherOption() {
        XCTAssertTrue(WorkoutType.allCases.contains(.other))
        XCTAssertTrue(WorkoutType.allCases.contains(.kettlebell))
        XCTAssertEqual(WorkoutType.allCases.count, 12)
    }

    func testSelectableWorkoutTypesExcludeProtocolName() {
        // "Norwegian 4x4" is the protocol, not an exercise — it must never be
        // offered in pickers, but stays in the enum so old logs decode.
        XCTAssertFalse(WorkoutType.selectableCases.contains(.norwegian4x4))
        XCTAssertEqual(WorkoutType.selectableCases.count, WorkoutType.allCases.count - 1)
        XCTAssertNotNil(WorkoutType(rawValue: "Norwegian 4x4"))
    }

    func testDefaultWorkoutTypeDrivesSelectedTypeOnLaunch() {
        UserDefaults.standard.set(WorkoutType.kettlebell.rawValue, forKey: "defaultWorkoutTypeRaw")

        let vm = TimerViewModel()

        XCTAssertEqual(vm.selectedWorkoutType, .kettlebell)
    }

    func testResolvedDefaultFallsBackToPreferredModality() {
        // Users who onboarded before the explicit default existed only have a
        // modality stored — it must keep working as the default.
        UserDefaults.standard.set(TrainingModality.bike.rawValue, forKey: "preferredModalityRaw")

        let vm = TimerViewModel()

        XCTAssertEqual(vm.resolvedDefaultWorkoutType, .cycle)
        XCTAssertEqual(vm.selectedWorkoutType, .cycle)
    }

    func testSetDefaultWorkoutTypeSyncsModality() {
        let vm = TimerViewModel()

        vm.setDefaultWorkoutType(.kettlebell)

        XCTAssertEqual(vm.defaultWorkoutType, .kettlebell)
        XCTAssertEqual(vm.preferredModality, .kettlebell)
        XCTAssertEqual(vm.selectedWorkoutType, .kettlebell)
    }

    func testSetPreferredModalitySyncsDefaultWorkoutType() {
        let vm = TimerViewModel()

        vm.setPreferredModality(.rowing)

        XCTAssertEqual(vm.defaultWorkoutType, .rowing)
        XCTAssertEqual(vm.resolvedDefaultWorkoutType, .rowing)
    }

    func testWorkoutLogMigrationFromLegacySchemaPreservesEntry() {
        let legacyJson = "[{\"completedAt\":\"2026-02-18T10:00:00Z\"}]"
        UserDefaults.standard.set(legacyJson, forKey: "workoutLogEntriesData")

        let vm = TimerViewModel()

        XCTAssertEqual(vm.workoutLogEntries.count, 1)
        XCTAssertEqual(vm.workoutLogEntries.first?.workoutType, .norwegian4x4)
        XCTAssertEqual(vm.workoutLogEntries.first?.notes, "")
    }

    func testWorkoutLogMigrationDefaultsUnknownWorkoutTypeToNorwegian4x4() {
        let legacyJson = "[{\"completedAt\":\"2026-02-18T10:00:00Z\",\"workoutType\":\"SkiErg\",\"notes\":\"  hard effort  \"}]"
        UserDefaults.standard.set(legacyJson, forKey: "workoutLogEntriesData")

        let vm = TimerViewModel()

        XCTAssertEqual(vm.workoutLogEntries.count, 1)
        XCTAssertEqual(vm.workoutLogEntries.first?.workoutType, .norwegian4x4)
        XCTAssertEqual(vm.workoutLogEntries.first?.notes, "hard effort")
    }

    func testUserAgeSanitizationDoesNotLoopAndStaysBounded() {
        let vm = TimerViewModel()

        vm.userAge = 5
        XCTAssertEqual(vm.userAge, TimerViewModel.minimumSupportedAge)

        vm.userAge = 150
        XCTAssertEqual(vm.userAge, TimerViewModel.maximumSupportedAge)

        vm.userAge = 40
        XCTAssertEqual(vm.userAge, 40)
    }

    func testInvalidReminderWeekdaysAreFilteredOut() {
        // Out-of-range weekday values from stored strings must be dropped so the
        // schedule only ever contains valid 1...7 days.
        let vm = TimerViewModel()
        vm.workoutReminderWeekdays = "999,3,0,7"

        XCTAssertEqual(vm.selectedWeekdaysList.sorted(), [3, 7])
        XCTAssertEqual(vm.workoutReminderMode, .weeklyWeekday)
    }

    // MARK: - Reminder family toggles (4.6)

    func testFamilyFlagsSyncToMasterOnFirstLaunch() {
        // Reminders off + factory-default family flags (true) would show three
        // ON toggles that do nothing — the migration must pull them down.
        let vm = TimerViewModel()

        XCTAssertFalse(vm.workoutRemindersEnabled)
        XCTAssertFalse(vm.nightBeforeReminderEnabled)
        XCTAssertFalse(vm.morningOfReminderEnabled)
        XCTAssertFalse(vm.comebackNudgesEnabled)
    }

    func testEnablingOneFamilyTurnsMasterOn() {
        let vm = TimerViewModel()

        vm.morningOfReminderEnabled = true

        XCTAssertTrue(vm.workoutRemindersEnabled)
        XCTAssertFalse(vm.nightBeforeReminderEnabled)
        XCTAssertFalse(vm.comebackNudgesEnabled)
    }

    func testDisablingLastFamilyTurnsMasterOff() {
        let vm = TimerViewModel()
        vm.nightBeforeReminderEnabled = true
        XCTAssertTrue(vm.workoutRemindersEnabled)

        vm.nightBeforeReminderEnabled = false

        XCTAssertFalse(vm.workoutRemindersEnabled)
    }

    func testEnablingMasterDirectlyRaisesAllFamilies() {
        // Onboarding sets the master straight to true — with every family off
        // that must raise all three, or nothing would ever be scheduled.
        let vm = TimerViewModel()

        vm.workoutRemindersEnabled = true

        XCTAssertTrue(vm.nightBeforeReminderEnabled)
        XCTAssertTrue(vm.morningOfReminderEnabled)
        XCTAssertTrue(vm.comebackNudgesEnabled)
    }

    // MARK: - Settings row summaries (4.6)

    func testReminderDaysSummaryFormatsSelectedDays() {
        let vm = TimerViewModel()
        XCTAssertEqual(vm.reminderDaysSummary, "Off")

        vm.workoutReminderWeekdays = "3,5"   // Tuesday, Thursday
        vm.nightBeforeReminderEnabled = true // master follows

        XCTAssertEqual(vm.reminderDaysSummary, "Tue · Thu")
    }

    func testIntervalPlanSummaryFormatsCountAndDuration() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 4
        vm.highIntensityDuration = 240

        XCTAssertEqual(vm.intervalPlanSummary, "4 × 4:00")

        vm.numberOfIntervals = 3
        vm.highIntensityDuration = 90

        XCTAssertEqual(vm.intervalPlanSummary, "3 × 1:30")
    }

    func testReminderModeAndDayTransitionsDoNotOscillate() {
        let vm = TimerViewModel()
        vm.workoutRemindersEnabled = false

        vm.workoutReminderMode = .weeklyWeekday
        let weeklyDay = vm.workoutReminderWeekday
        XCTAssertTrue((1...7).contains(weeklyDay))

        vm.workoutReminderMode = .weeklyWeekday
        XCTAssertEqual(vm.workoutReminderWeekday, weeklyDay)
    }

    // MARK: - Streak calculation

    private func makeEntry(_ date: Date) -> WorkoutLogEntry {
        WorkoutLogEntry(completedAt: date, workoutType: .norwegian4x4,
                        notes: "", modality: nil, intervalPerformances: nil)
    }

    func testStreakBreaksOnMissedMiddleWeek() {
        // Trained this week and two weeks ago, but skipped last week: the missed
        // week must break the streak (regression for the head-gap-forgiveness bug).
        let vm = TimerViewModel()
        let cal = Calendar.current, now = Date()
        vm.workoutLogEntries = [
            makeEntry(now),
            makeEntry(cal.date(byAdding: .weekOfYear, value: -2, to: now)!),
        ]
        XCTAssertEqual(vm.currentWeekStreak, 1)
    }

    func testStreakCountsConsecutiveWeeks() {
        let vm = TimerViewModel()
        let cal = Calendar.current, now = Date()
        vm.workoutLogEntries = [
            makeEntry(now),
            makeEntry(cal.date(byAdding: .weekOfYear, value: -1, to: now)!),
            makeEntry(cal.date(byAdding: .weekOfYear, value: -2, to: now)!),
        ]
        XCTAssertEqual(vm.currentWeekStreak, 3)
    }

    func testStreakForgivesNotYetTrainedCurrentWeek() {
        // No workout yet this week, but trained the prior two weeks: the head gap
        // legitimately forgives the current week, so the streak is 2.
        let vm = TimerViewModel()
        let cal = Calendar.current, now = Date()
        vm.workoutLogEntries = [
            makeEntry(cal.date(byAdding: .weekOfYear, value: -1, to: now)!),
            makeEntry(cal.date(byAdding: .weekOfYear, value: -2, to: now)!),
        ]
        XCTAssertEqual(vm.currentWeekStreak, 2)
    }

    // MARK: - Performance logging (Phase 1)

    func testSpeedConversionRoundTrips() {
        // 10 km/h ≈ 6.2137 mph; round-trip must return the original value.
        let kmh = 10.0
        let mph = PerformanceUnits.kmhToMph(kmh)
        XCTAssertEqual(mph, 6.21371, accuracy: 0.0001)
        XCTAssertEqual(PerformanceUnits.mphToKmh(mph), kmh, accuracy: 0.000001)
    }

    func testModalityMetricLocaleConversionFlag() {
        // Distance-based modalities convert with locale; cadence/level do not.
        XCTAssertTrue(TrainingModality.treadmill.performanceMetric.localeConverted)
        XCTAssertTrue(TrainingModality.outdoorRun.performanceMetric.localeConverted)
        XCTAssertFalse(TrainingModality.bike.performanceMetric.localeConverted)
        XCTAssertFalse(TrainingModality.stairClimber.performanceMetric.localeConverted)
        XCTAssertEqual(TrainingModality.treadmill.performanceMetric.imperialUnit, "mph")
    }

    func testWorkoutLogEntryCodableRoundTripWithPerformance() {
        let entry = WorkoutLogEntry(
            completedAt: Date(timeIntervalSince1970: 1_700_000_000),
            workoutType: .treadmill,
            notes: "tempo",
            modality: .treadmill,
            intervalPerformances: [
                IntervalPerformance(intervalNumber: 1, primary: 12.0),
                IntervalPerformance(intervalNumber: 2, primary: 12.5),
            ]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try! encoder.encode(entry)
        let decoded = try! decoder.decode(WorkoutLogEntry.self, from: data)

        XCTAssertEqual(decoded.modality, .treadmill)
        XCTAssertEqual(decoded.intervalPerformances?.count, 2)
        XCTAssertEqual(decoded.intervalPerformances?[1].primary, 12.5)
        XCTAssertEqual(decoded, entry)
    }

    func testLegacyEntryWithoutPerformanceDecodesToNil() {
        // An entry encoded before performance logging existed has no modality /
        // intervalPerformances keys. Synthesized Codable must decode them as nil.
        let legacyJSON = """
        [{"id":"\(UUID().uuidString)","completedAt":"2026-01-01T08:00:00Z",
          "workoutType":"Norwegian 4x4","notes":""}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entries = try! decoder.decode([WorkoutLogEntry].self,
                                          from: legacyJSON.data(using: .utf8)!)
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].modality)
        XCTAssertNil(entries[0].intervalPerformances)
    }

    func testAveragePrimaryIgnoresBlanks() {
        let entry = WorkoutLogEntry(
            workoutType: .treadmill,
            notes: "",
            modality: .treadmill,
            intervalPerformances: [
                IntervalPerformance(intervalNumber: 1, primary: 10),
                IntervalPerformance(intervalNumber: 2, primary: nil),
                IntervalPerformance(intervalNumber: 3, primary: 14),
            ]
        )
        XCTAssertEqual(entry.averagePrimaryPerformance, 12.0)
    }

    func testLastLoggedPerformanceReturnsMostRecentForModality() {
        let vm = TimerViewModel()
        vm.workoutLogEntries = [
            WorkoutLogEntry(completedAt: Date(timeIntervalSince1970: 200),
                            workoutType: .treadmill, notes: "", modality: .treadmill,
                            intervalPerformances: [IntervalPerformance(intervalNumber: 1, primary: 13)]),
            WorkoutLogEntry(completedAt: Date(timeIntervalSince1970: 100),
                            workoutType: .treadmill, notes: "", modality: .treadmill,
                            intervalPerformances: [IntervalPerformance(intervalNumber: 1, primary: 11)]),
        ]
        XCTAssertEqual(vm.lastLoggedPerformance(for: .treadmill)?.first?.primary, 13)
        XCTAssertNil(vm.lastLoggedPerformance(for: .bike))
    }

    // MARK: - Performance capture (Phase 2)

    func testStampAllIntervalsFillsEveryInterval() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 4
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        XCTAssertEqual(vm.performanceDraft.count, 4)

        vm.performanceSetAll = 12.0
        vm.stampAllIntervals()
        XCTAssertEqual(vm.performanceDraft, [12.0, 12.0, 12.0, 12.0])
    }

    func testSavePersistsPerformanceInCanonicalUnitsMetric() {
        let vm = TimerViewModel()
        vm.unitPreference = .metric              // display == canonical (km/h)
        vm.numberOfIntervals = 2
        vm.finishWorkout()
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        vm.performanceDraft = [12.0, 13.0]
        vm.completeWorkoutReview()

        let entry = vm.workoutLogEntries.first
        XCTAssertEqual(entry?.modality, .treadmill)
        XCTAssertEqual(entry?.intervalPerformances?.map { $0.primary }, [12.0, 13.0])
        XCTAssertEqual(entry?.intervalPerformances?.map { $0.intervalNumber }, [1, 2])
    }

    func testImperialSpeedStoredAsCanonicalKmh() {
        let vm = TimerViewModel()
        vm.unitPreference = .imperial            // entered mph -> stored km/h
        vm.numberOfIntervals = 1
        vm.finishWorkout()
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        vm.performanceDraft = [6.21371]          // mph ≈ 10 km/h
        vm.completeWorkoutReview()

        let stored = vm.workoutLogEntries.first?.intervalPerformances?.first?.primary
        XCTAssertEqual(stored ?? 0, 10.0, accuracy: 0.001)
    }

    func testBlankDraftStoresNoPerformances() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 3
        vm.finishWorkout()
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()             // all nil (no prior data)
        vm.completeWorkoutReview()

        XCTAssertNil(vm.workoutLogEntries.first?.intervalPerformances)
    }

    // MARK: - Automatic completion saving

    private func completedWorkout(sampleCount: Int = 5) -> TimerViewModel {
        let vm = TimerViewModel()
        vm.audioMode = .silent
        vm.hapticsEnabled = false
        vm.cooldownEnabled = false
        vm.unitPreference = .metric
        vm.setDefaultWorkoutType(.treadmill)
        vm.workoutStartDate = Date(timeIntervalSince1970: 1_800_000_000)
        vm.elapsedHighIntensityTime = 240
        vm.completedSeries = HeartRateSeries(
            samples: (0..<sampleCount).map { .init(t: Double($0 * 2), bpm: 150) },
            spans: [.init(kind: "work", workNumber: 1, start: 0, end: 240,
                          targetLo: 140, targetHi: 170)],
            startedAt: vm.workoutStartDate!
        )
        vm.finishWorkout()
        return vm
    }

    func testCompletionPersistsWorkoutAndSeriesBeforeReview() throws {
        let vm = completedWorkout()
        let entry = try XCTUnwrap(vm.workoutLogEntries.first)
        defer { HeartRateSeriesStore.delete(for: entry.id) }
        XCTAssertTrue(vm.showPostWorkoutSummary)
        XCTAssertNotNil(vm.completedSeries)
        XCTAssertEqual(vm.currentStreak, 1)
        XCTAssertNil(entry.intervalPerformances, "Autosave must not copy prior workout settings")

        let reloaded = TimerViewModel()
        XCTAssertEqual(reloaded.workoutLogEntries.first?.id, entry.id)
        XCTAssertEqual(reloaded.workoutLogEntries.first?.sessionBreakdown?.totalDuration, 240)
        XCTAssertEqual(HeartRateSeriesStore.load(for: entry.id), vm.completedSeries)
    }

    func testCompletionPreservesTimelineWithSparseOrNoHeartRate() throws {
        for sampleCount in [0, 4] {
            let vm = completedWorkout(sampleCount: sampleCount)
            let id = try XCTUnwrap(vm.completedWorkoutEntryID)
            let saved = try XCTUnwrap(HeartRateSeriesStore.load(for: id))
            XCTAssertEqual(saved.spans.count, 1)
            XCTAssertEqual(saved.samples.count, sampleCount)
            XCTAssertNil(vm.workoutLogEntries.first { $0.id == id }?.hrSummary)
            HeartRateSeriesStore.delete(for: id)
        }
    }

    func testRepeatedCompletionAndDoneDoNotDuplicateWorkout() throws {
        let vm = completedWorkout()
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        defer { HeartRateSeriesStore.delete(for: id) }
        vm.finishWorkout()
        vm.workoutNotesDraft = "  Saved after review  "
        vm.preparePerformanceDraft()
        vm.performanceDraft[0] = 12
        vm.completeWorkoutReview()
        vm.completeWorkoutReview()

        let reloaded = TimerViewModel()
        XCTAssertEqual(reloaded.workoutLogEntries.count, 1)
        XCTAssertEqual(reloaded.workoutLogEntries.first?.id, id)
        XCTAssertEqual(reloaded.workoutLogEntries.first?.notes, "Saved after review")
        XCTAssertEqual(reloaded.workoutLogEntries.first?.intervalPerformances?.first?.primary, 12)
        XCTAssertNotNil(HeartRateSeriesStore.load(for: id))
        XCTAssertNil(vm.completedSeries)
        XCTAssertFalse(vm.showPostWorkoutSummary)
    }

    func testDismissingSummaryKeepsWorkoutAndSavesReview() throws {
        let vm = completedWorkout()
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        defer { HeartRateSeriesStore.delete(for: id) }
        vm.workoutNotesDraft = "Swipe to close"
        vm.postWorkoutSummaryDidDismiss()

        XCTAssertFalse(vm.showPostWorkoutSummary)
        XCTAssertNil(vm.workoutStartDate)
        XCTAssertEqual(TimerViewModel().workoutLogEntries.first?.notes, "Swipe to close")
    }

    func testDeletingCompletedWorkoutRemovesPersistedEntryAndSeries() throws {
        let vm = completedWorkout()
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        vm.deleteCurrentWorkoutAndResetSession()
        vm.postWorkoutSummaryDidDismiss()
        vm.completeWorkoutReview()

        XCTAssertTrue(TimerViewModel().workoutLogEntries.isEmpty)
        XCTAssertNil(HeartRateSeriesStore.load(for: id))
        XCTAssertEqual(vm.currentStreak, 0)
        XCTAssertFalse(vm.showPostWorkoutSummary)
        XCTAssertFalse(vm.showMilestoneCelebration)
        XCTAssertFalse(vm.showWeeklyStreaks)
    }

    func testResetKeepsCompletedWorkoutButDoesNotLogUnfinishedOne() throws {
        let vm = completedWorkout()
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        defer { HeartRateSeriesStore.delete(for: id) }
        vm.reset()
        vm.startTimer()
        vm.reset()

        XCTAssertEqual(TimerViewModel().workoutLogEntries.map(\.id), [id])
    }

    func testDeletingOneOfTwoSameDayWorkoutsKeepsTheOther() throws {
        let vm = completedWorkout()
        let firstID = try XCTUnwrap(vm.completedWorkoutEntryID)
        defer { HeartRateSeriesStore.delete(for: firstID) }
        vm.reset()
        vm.finishWorkout()
        let secondID = try XCTUnwrap(vm.completedWorkoutEntryID)
        XCTAssertNotEqual(firstID, secondID)
        vm.deleteWorkoutLogEntry(id: secondID)
        XCTAssertEqual(TimerViewModel().workoutLogEntries.map(\.id), [firstID])
    }

}

// MARK: - Heart-rate series recording

final class HeartRateSeriesTests: XCTestCase {

    private func span(_ kind: String, _ start: Double, _ end: Double,
                      work: Int = 0, lo: Int = 0, hi: Int = 0) -> HeartRateSeries.IntervalSpan {
        .init(kind: kind, workNumber: work, start: start, end: end, targetLo: lo, targetHi: hi)
    }

    func testRecorderBucketsSamplesToTwoSeconds() {
        let r = HeartRateSeriesRecorder()
        r.record(bpm: 100, at: 0)
        r.record(bpm: 101, at: 0.5)   // dropped: same bucket
        r.record(bpm: 102, at: 1.9)   // dropped
        r.record(bpm: 103, at: 2.0)   // kept
        r.record(bpm: 104, at: 3.9)   // dropped
        r.record(bpm: 105, at: 4.1)   // kept
        XCTAssertEqual(r.samples.map(\.bpm), [100, 103, 105])
    }

    func testRecorderRejectsGarbage() {
        let r = HeartRateSeriesRecorder()
        r.record(bpm: 0, at: 0)
        r.record(bpm: -10, at: 2)
        r.record(bpm: 120, at: -1)
        XCTAssertTrue(r.samples.isEmpty)
    }

    func testRecorderBuildsSpansAcrossIntervalChanges() {
        let r = HeartRateSeriesRecorder()
        r.beginInterval(kind: "warmup", workNumber: 0, targetLo: 0, targetHi: 0, at: 0)
        r.beginInterval(kind: "work", workNumber: 1, targetLo: 150, targetHi: 170, at: 600)
        r.beginInterval(kind: "recovery", workNumber: 0, targetLo: 110, targetHi: 130, at: 840)
        let series = r.finish(at: 1020)
        XCTAssertEqual(series.spans.map(\.kind), ["warmup", "work", "recovery"])
        XCTAssertEqual(series.spans[1].start, 600)
        XCTAssertEqual(series.spans[1].end, 840)
        XCTAssertEqual(series.spans[1].workNumber, 1)
        XCTAssertEqual(series.spans[2].end, 1020)
    }

    func testRecorderDropsZeroLengthSpans() {
        let r = HeartRateSeriesRecorder()
        r.beginInterval(kind: "warmup", workNumber: 0, targetLo: 0, targetHi: 0, at: 0)
        // Double advance in the same instant (skip tapped twice).
        r.beginInterval(kind: "work", workNumber: 1, targetLo: 150, targetHi: 170, at: 300)
        r.beginInterval(kind: "recovery", workNumber: 0, targetLo: 110, targetHi: 130, at: 300.1)
        let series = r.finish(at: 500)
        XCTAssertEqual(series.spans.map(\.kind), ["warmup", "recovery"])
    }

    func testInZonePctCountsOnlyInZoneTime() {
        // 10 samples 2 s apart: first 5 below target, last 5 inside.
        let samples = (0..<10).map {
            HeartRateSeries.Sample(t: Double($0 * 2), bpm: $0 < 5 ? 140 : 160)
        }
        let s = HeartRateSeries(
            samples: samples,
            spans: [span("work", 0, 18, work: 1, lo: 150, hi: 170)],
            startedAt: Date(timeIntervalSince1970: 0))
        // 9 gaps of 2 s; the first 4 lead from below-zone samples, gap 5 leads
        // from sample index 4 (below), gaps 6-9 lead from in-zone samples.
        XCTAssertEqual(HeartRateSeriesAnalytics.inZonePct(s, span: s.spans[0]), 44)
    }

    func testInZonePctNilWithoutTargetOrSamples() {
        let s = HeartRateSeries(
            samples: [.init(t: 0, bpm: 100), .init(t: 2, bpm: 100)],
            spans: [span("warmup", 0, 10), span("work", 20, 30, work: 1, lo: 150, hi: 170)],
            startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(HeartRateSeriesAnalytics.inZonePct(s, span: s.spans[0]), "no target")
        XCTAssertNil(HeartRateSeriesAnalytics.inZonePct(s, span: s.spans[1]), "no samples in span")
    }

    func testTimeToZone() {
        let samples = [
            HeartRateSeries.Sample(t: 100, bpm: 120),
            HeartRateSeries.Sample(t: 130, bpm: 149),
            HeartRateSeries.Sample(t: 160, bpm: 151),
        ]
        let work = span("work", 100, 340, work: 1, lo: 150, hi: 170)
        let s = HeartRateSeries(samples: samples, spans: [work],
                                startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(HeartRateSeriesAnalytics.timeToZone(s, span: work), 60)
    }

    func testTimeToZoneNilWhenNeverReached() {
        let samples = [HeartRateSeries.Sample(t: 100, bpm: 120)]
        let work = span("work", 100, 340, work: 1, lo: 150, hi: 170)
        let s = HeartRateSeries(samples: samples, spans: [work],
                                startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(HeartRateSeriesAnalytics.timeToZone(s, span: work))
    }

    func testSparklineDownsamples() {
        let flat = HeartRateSeriesAnalytics.sparkline(from: Array(repeating: 150.0, count: 800), points: 40)
        XCTAssertEqual(flat.count, 40)
        XCTAssertTrue(flat.allSatisfy { $0 == 150 })

        let short = HeartRateSeriesAnalytics.sparkline(from: [100, 110, 120], points: 40)
        XCTAssertEqual(short, [100, 110, 120], "shorter than target passes through")
    }

    func testSummaryNilForTinySeries() {
        let s = HeartRateSeries(samples: [.init(t: 0, bpm: 100)], spans: [],
                                startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertNil(HeartRateSeriesAnalytics.summary(for: s))
    }

    func testSummaryStats() {
        let samples = (0..<100).map { HeartRateSeries.Sample(t: Double($0 * 2), bpm: 150) }
        let s = HeartRateSeries(
            samples: samples,
            spans: [span("work", 0, 200, work: 1, lo: 140, hi: 160)],
            startedAt: Date(timeIntervalSince1970: 0))
        let summary = HeartRateSeriesAnalytics.summary(for: s)
        XCTAssertEqual(summary?.avgBPM, 150)
        XCTAssertEqual(summary?.maxBPM, 150)
        XCTAssertEqual(summary?.workInZonePct, 100)
        XCTAssertEqual(summary?.sparkline.count, 40)
    }

    func testStoreRoundTripAndDelete() {
        let id = UUID()
        let s = HeartRateSeries(
            samples: [.init(t: 0, bpm: 100), .init(t: 2, bpm: 110)],
            spans: [span("work", 0, 240, work: 1, lo: 150, hi: 170)],
            startedAt: Date(timeIntervalSince1970: 1000))
        HeartRateSeriesStore.save(s, for: id)
        XCTAssertEqual(HeartRateSeriesStore.load(for: id), s)
        HeartRateSeriesStore.delete(for: id)
        XCTAssertNil(HeartRateSeriesStore.load(for: id))
    }
}
