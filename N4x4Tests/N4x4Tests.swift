import XCTest
import UserNotifications
import AVFoundation
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
        try? FileManager.default.removeItem(at: TimerViewModel.defaultCheckpointURL.deletingLastPathComponent())
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
            "cooldownDuration", "discardedPhoneWorkoutIDs", "importedWatchWorkoutIDs", "discardedWatchWorkoutIDs",
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

        vm.workoutStartDate = Date()
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

        vm.workoutStartDate = Date()
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

        vm.workoutStartDate = Date()
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
        XCTAssertEqual(WorkoutType.allCases.count, 13)
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

    func testEllipticalPreferenceRestoresWithoutChangingHeartRateTargets() {
        let vm = TimerViewModel()
        vm.setDefaultWorkoutType(.other)
        let workTarget = vm.highIntensityTargetRange
        let recoveryTarget = vm.recoveryTargetRange

        vm.setDefaultWorkoutType(.elliptical)

        XCTAssertTrue(WorkoutType.selectableCases.contains(.elliptical))
        XCTAssertEqual(vm.preferredModality, .elliptical)
        XCTAssertEqual(vm.highIntensityTargetRange, workTarget)
        XCTAssertEqual(vm.recoveryTargetRange, recoveryTarget)
        let restored = TimerViewModel()
        XCTAssertEqual(restored.selectedWorkoutType, .elliptical)
        XCTAssertEqual(restored.preferredModality, .elliptical)
    }

    func testEllipticalReviewPersistsResistanceWithoutSpeedConversion() throws {
        let vm = TimerViewModel()
        vm.unitPreference = .imperial
        vm.numberOfIntervals = 2
        vm.setDefaultWorkoutType(.elliptical)
        vm.finishWorkout()
        vm.preparePerformanceDraft()
        XCTAssertEqual(vm.currentPerformanceMetric.label, "Resistance")
        XCTAssertEqual(vm.currentPerformanceUnit, "level")
        vm.performanceDraft = [8, 12]
        XCTAssertTrue(vm.completeWorkoutReview())

        let entry = try XCTUnwrap(vm.workoutLogEntries.first)
        XCTAssertEqual(entry.workoutType, .elliptical)
        XCTAssertEqual(entry.modality, .elliptical)
        XCTAssertEqual(entry.intervalPerformances?.map(\.primary), [8, 12])
        let restored = TimerViewModel()
        let restoredEntry = try XCTUnwrap(restored.workoutLogEntries.first)
        XCTAssertEqual(restoredEntry.id, entry.id)
        XCTAssertEqual(restoredEntry.workoutType, .elliptical)
        XCTAssertEqual(restoredEntry.modality, .elliptical)
        XCTAssertEqual(restoredEntry.intervalPerformances, entry.intervalPerformances)
        XCTAssertEqual(restored.displayValue(12, for: .elliptical), 12)
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
        vm.numberOfIntervals = 1
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

final class WorkoutExportTests: XCTestCase {
    private func object(_ export: WorkoutExport) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: export.jsonData()) as? [String: Any])
    }

    func testFullExportPreservesAllStoredWorkoutAndRecordingFields() throws {
        let start = Date(timeIntervalSince1970: 1_790_000_000.125)
        var timing = WorkoutActivityTiming(startedAt: start)
        timing.pause(at: start + 20)
        timing.resume(at: start + 40)
        timing.finish(at: start + 90)
        let samples = (0..<35).map { HeartRateSeries.Sample(t: Double($0 * 2), bpm: 140.25 + Double($0)) }
        let spans: [HeartRateSeries.IntervalSpan] = [
            .init(kind: "warmup", workNumber: 0, start: 0, end: 10, targetLo: 0, targetHi: 0),
            .init(kind: "work", workNumber: 1, start: 10, end: 60, targetLo: 150, targetHi: 170),
            .init(kind: "recovery", workNumber: 0, start: 60, end: 80, targetLo: 110, targetHi: 130),
            .init(kind: "cooldown", workNumber: 0, start: 80, end: 90, targetLo: 0, targetHi: 0)
        ]
        let series = HeartRateSeries(samples: samples, spans: spans, startedAt: start, activityTiming: timing)
        var health = HealthWorkoutExport(start: start, end: start + 90, requested: true)
        health.state = .saved
        health.attempts = 2
        health.lastAttempt = start + 91
        health.healthID = UUID()
        health.savedAt = start + 92
        health.heartRateContent = .included
        health.activityTiming = timing
        health.expectedActiveDuration = 70
        let entry = WorkoutLogEntry(completedAt: start + 90, workoutType: .treadmill,
            notes: "Felt strong 🏃\nIncline 4%", sessionBreakdown: .init(totalDuration: 70,
                warmupDuration: 10, highIntensityDuration: 30, recoveryDuration: 20,
                cooldownDuration: 10, cooldownSkipped: false), modality: .treadmill,
            intervalPerformances: [.init(intervalNumber: 1, primary: 12.345, secondary: 4, note: "First effort"),
                                   .init(intervalNumber: 4, note: "Unmatched interval note")],
            hrSummary: HeartRateSeriesAnalytics.summary(for: series), endedEarly: true, healthExport: health)
        let root = try object(WorkoutExport(entry: entry, series: series, exportedAt: start + 100))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return try XCTUnwrap(formatter.date(from: value))
        }
        // Round-trip the entire original documents, not a hand-picked subset.
        let exportedEntry = try decoder.decode(WorkoutLogEntry.self,
            from: JSONSerialization.data(withJSONObject: XCTUnwrap(root["workout"])))
        let exportedSeries = try decoder.decode(HeartRateSeries.self,
            from: JSONSerialization.data(withJSONObject: XCTUnwrap(root["recording"])))
        XCTAssertEqual(exportedEntry, entry)
        XCTAssertEqual(exportedSeries, series)
        XCTAssertEqual(root["schemaVersion"] as? Int, 1)
        XCTAssertEqual(root["recordingStatus"] as? String, "heartRateAvailable")
        let metric = try XCTUnwrap(root["performanceMetric"] as? [String: Any])
        XCTAssertEqual(metric["primaryUnit"] as? String, "km/h")
        let stages = try XCTUnwrap(root["stages"] as? [[String: Any]])
        XCTAssertEqual(stages.map { $0["kind"] as? String }, ["warmup", "work", "recovery", "cooldown"])
        XCTAssertEqual(stages[1]["elapsedDurationSeconds"] as? Double, 50)
        XCTAssertEqual(stages[1]["activeDurationSeconds"] as? Double, 30)
        XCTAssertEqual(stages[1]["inZonePercent"] as? Int,
                       HeartRateSeriesAnalytics.inZonePct(series, span: spans[1]))
        XCTAssertEqual(stages[1]["timeToZoneSeconds"] as? Double,
                       HeartRateSeriesAnalytics.timeToZone(series, span: spans[1]))
        XCTAssertNil(stages[0]["inZonePercent"])
        XCTAssertNil(stages[3]["averageBPM"], "No measurements must not become zero BPM")
    }

    func testLegacyExportDoesNotInventTimelineOrMeasurements() throws {
        let entry = WorkoutLogEntry(workoutType: .run, notes: "An older workout",
            intervalPerformances: [.init(intervalNumber: 2, primary: 10, note: "Still available")],
            hrSummary: .init(avgBPM: 160, maxBPM: 175, workInZonePct: 80, sparkline: [155, 165]))
        let root = try object(WorkoutExport(entry: entry, series: nil))
        XCTAssertEqual(root["recordingStatus"] as? String, "unavailable")
        XCTAssertNil(root["recording"])
        XCTAssertNil(root["stages"])
        let saved = try XCTUnwrap(root["workout"] as? [String: Any])
        XCTAssertNotNil(saved["hrSummary"])
        XCTAssertNotNil(saved["intervalPerformances"])
        XCTAssertNil(saved["endedEarly"])
    }

    func testTimelineWithoutHeartRateStillExportsEveryStageAndNoInventedActiveTime() throws {
        let spans: [HeartRateSeries.IntervalSpan] = [
            .init(kind: "work", workNumber: 1, start: 0, end: 60, targetLo: 150, targetHi: 170),
            .init(kind: "recovery", workNumber: 0, start: 60, end: 80, targetLo: 110, targetHi: 130)
        ]
        let series = HeartRateSeries(samples: [], spans: spans, startedAt: Date())
        let entry = WorkoutLogEntry(workoutType: .elliptical, notes: "", modality: .elliptical)
        let export = WorkoutExport(entry: entry, series: series)
        let root = try object(export)
        XCTAssertEqual(export.performanceMetric.primaryUnit, "level")
        XCTAssertEqual(export.performanceMetric.primaryLabel, "Resistance")
        XCTAssertEqual(root["recordingStatus"] as? String, "timelineOnly")
        let stages = try XCTUnwrap(root["stages"] as? [[String: Any]])
        XCTAssertEqual(stages.count, 2)
        XCTAssertEqual(stages[0]["sampleCount"] as? Int, 0)
        XCTAssertNil(stages[0]["activeDurationSeconds"])
        XCTAssertNil(stages[0]["averageBPM"])
        XCTAssertNil(stages[0]["timeToZoneSeconds"])
    }

    func testActiveStageTimeCanUseSavedHealthTimingWithoutBridgingPause() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        var timing = WorkoutActivityTiming(startedAt: start)
        timing.pause(at: start + 10)
        timing.resume(at: start + 40)
        timing.finish(at: start + 60)
        var health = HealthWorkoutExport(start: start, end: start + 60, requested: true)
        health.activityTiming = timing
        let entry = WorkoutLogEntry(workoutType: .cycle, notes: "", healthExport: health)
        let series = HeartRateSeries(samples: [], spans: [
            .init(kind: "work", workNumber: 1, start: 0, end: 60, targetLo: 150, targetHi: 170)
        ], startedAt: start)
        let export = WorkoutExport(entry: entry, series: series)
        XCTAssertEqual(export.stages?.first?.activeDurationSeconds, 30)
        XCTAssertEqual(export.stages?.first?.elapsedDurationSeconds, 60)
    }

    func testFilenameUsesStableWorkoutIdentity() {
        let entry = WorkoutLogEntry(workoutType: .run, notes: "")
        let file = WorkoutExportFile(entry: entry, series: nil)
        XCTAssertEqual(file.filename, "N4x4-Workout-\(entry.id.uuidString).json")
    }
}

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

// MARK: - Completion, recovery and durable saving

extension N4x4Tests {
    private func recoveryViewModel(cooldown: Bool = false, warmup: Double = 0,
                                   count: Int = 1,
                                   seriesSaver: @escaping (HeartRateSeries, UUID) -> Bool = { HeartRateSeriesStore.save($0, for: $1) }) -> TimerViewModel {
        UserDefaults.standard.set(false, forKey: "healthKitEnabled")
        UserDefaults.standard.set(true, forKey: "healthKitUserOptedOut")
        UserDefaults.standard.set(false, forKey: "appleSensorHREnabled")
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        UserDefaults.standard.set(false, forKey: "workoutRemindersEnabled")
        UserDefaults.standard.set(false, forKey: "liveActivitiesEnabled")
        let vm = TimerViewModel(seriesSaver: seriesSaver)
        vm.audioMode = .silent
        vm.hapticsEnabled = false
        vm.numberOfIntervals = count
        vm.warmupDuration = warmup
        vm.highIntensityDuration = 4
        vm.restDuration = 3
        vm.cooldownEnabled = cooldown
        vm.cooldownDuration = 60
        return vm
    }

    func testFinishAndSaveDuringWorkKeepsElapsedProgressWithoutFullWorkoutStreak() throws {
        let vm = recoveryViewModel()
        let start = Date()
        defer { vm.workoutLogEntries.forEach { HeartRateSeriesStore.delete(for: $0.id) }; vm.reset() }
        vm.startTimer(now: start)
        vm.finishAndSaveWorkout(now: start + 2)
        let entry = try XCTUnwrap(vm.workoutLogEntries.first)
        XCTAssertEqual(entry.sessionBreakdown?.totalDuration ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(entry.endedEarly, true)
        XCTAssertFalse(entry.countsTowardStreak)
        XCTAssertEqual(vm.currentWeekStreak, 0)
        XCTAssertTrue(vm.showPostWorkoutSummary)
        XCTAssertEqual(TimerViewModel().workoutLogEntries.first?.id, entry.id)
    }

    func testFinishInCooldownSavesFullWorkAndCountsTowardStreak() throws {
        let vm = recoveryViewModel(cooldown: true)
        let start = Date()
        defer { vm.workoutLogEntries.forEach { HeartRateSeriesStore.delete(for: $0.id) }; vm.reset() }
        vm.startTimer(now: start)
        vm.finishAndSaveWorkout(now: start + 10)
        let entry = try XCTUnwrap(vm.workoutLogEntries.first)
        XCTAssertEqual(entry.sessionBreakdown?.highIntensityDuration ?? 0, 4, accuracy: 0.001)
        XCTAssertEqual(entry.sessionBreakdown?.cooldownDuration ?? 0, 6, accuracy: 0.001)
        XCTAssertEqual(entry.sessionBreakdown?.cooldownSkipped, true)
        XCTAssertEqual(entry.endedEarly, false)
        XCTAssertEqual(vm.currentWeekStreak, 1)
    }

    func testDiscardActiveWorkoutRemovesRecoveryAndDoesNotLog() {
        let vm = recoveryViewModel()
        vm.startTimer()
        XCTAssertTrue(FileManager.default.fileExists(atPath: TimerViewModel.defaultCheckpointURL.path))
        vm.discardActiveWorkout()
        let restored = TimerViewModel()
        XCTAssertNil(restored.workoutStartDate)
        XCTAssertTrue(restored.workoutLogEntries.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: TimerViewModel.defaultCheckpointURL.path))
    }

    func testRunningWorkoutRecoversPausedWithItsOriginalPlanAndIdentity() throws {
        let vm = recoveryViewModel(warmup: 10, count: 2)
        let start = Date()
        vm.startTimer(now: start)
        vm.reconcileTimerState(now: start + 6, playAlarm: false)
        vm.timer?.cancel() // Simulate process loss without running the discard path.
        let id = try XCTUnwrap(vm.activeWorkoutID)
        let originalPlan = vm.intervals
        vm.numberOfIntervals = 7
        vm.highIntensityDuration = 300
        let restored = TimerViewModel()
        defer { restored.workoutLogEntries.forEach { HeartRateSeriesStore.delete(for: $0.id) }; restored.reset() }
        XCTAssertFalse(restored.isRunning)
        XCTAssertTrue(restored.showWorkoutRecovery)
        XCTAssertEqual(restored.activeWorkoutID, id)
        XCTAssertEqual(restored.intervals, originalPlan)
        XCTAssertEqual(restored.timeRemaining, 4, accuracy: 0.001)
        XCTAssertEqual(restored.elapsedWarmupTime, 6, accuracy: 0.001)
        restored.startTimer(now: start + 100)
        XCTAssertFalse(restored.showWorkoutRecovery)
        restored.finishAndSaveWorkout(now: start + 102)
        XCTAssertEqual(restored.workoutLogEntries.first?.id, id)
        XCTAssertEqual(restored.workoutLogEntries.first?.sessionBreakdown?.totalDuration ?? 0, 8, accuracy: 0.001)
    }

    func testPausedRecoveryFinishExcludesTimeAwayAndKeepsRecordedHeartRate() throws {
        let vm = recoveryViewModel(warmup: 30)
        let start = Date().addingTimeInterval(-2)
        vm.startTimer(now: start)
        vm.ingestHeartRate(151, from: .watch)
        vm.pause(now: start + 2)
        let restored = TimerViewModel()
        defer { restored.workoutLogEntries.forEach { HeartRateSeriesStore.delete(for: $0.id) }; restored.reset() }
        restored.finishAndSaveWorkout(now: start + 1_000)
        let entry = try XCTUnwrap(restored.workoutLogEntries.first)
        let series = try XCTUnwrap(HeartRateSeriesStore.load(for: entry.id))
        XCTAssertEqual(entry.sessionBreakdown?.totalDuration ?? 0, 2, accuracy: 0.001)
        XCTAssertEqual(entry.completedAt.timeIntervalSince(start), 2, accuracy: 0.001)
        XCTAssertEqual(series.samples.map(\.bpm), [151])
        XCTAssertEqual(series.spans.last?.end ?? 0, 2, accuracy: 0.001)
    }

    func testEveryTimerSettingChangeLeavesActivePlanAndCountdownIntact() {
        let changes: [(TimerViewModel) -> Void] = [
            { $0.numberOfIntervals += 1 }, { $0.warmupDuration += 60 },
            { $0.highIntensityDuration += 60 }, { $0.restDuration += 60 },
            { $0.cooldownEnabled.toggle() }, { $0.cooldownDuration += 60 }
        ]
        let vm = recoveryViewModel(warmup: 30)
        defer { vm.reset() }
        vm.startTimer()
        vm.pause()
        let plan = vm.intervals
        let remaining = vm.timeRemaining
        let id = vm.activeWorkoutID
        for change in changes {
            change(vm)
            XCTAssertEqual(vm.intervals, plan)
            XCTAssertEqual(vm.timeRemaining, remaining)
            XCTAssertEqual(vm.activeWorkoutID, id)
            XCTAssertNotNil(vm.workoutStartDate)
        }
        vm.reset()
        XCTAssertNotEqual(vm.intervals, plan, "New settings become the next plan")
    }

    func testCatchUpRecordsEveryBoundaryAndUsesActualCompletionTime() throws {
        let vm = recoveryViewModel(cooldown: true, warmup: 5, count: 2)
        let start = Date()
        defer { vm.workoutLogEntries.forEach { HeartRateSeriesStore.delete(for: $0.id) }; vm.reset() }
        vm.startTimer(now: start)
        vm.reconcileTimerState(now: start + 500, playAlarm: false)
        let entry = try XCTUnwrap(vm.workoutLogEntries.first)
        let series = try XCTUnwrap(HeartRateSeriesStore.load(for: entry.id))
        XCTAssertEqual(entry.sessionBreakdown?.totalDuration ?? 0, 76, accuracy: 0.001)
        XCTAssertEqual(entry.completedAt.timeIntervalSince(start), 76, accuracy: 0.001)
        XCTAssertEqual(series.spans.map(\.kind), ["warmup", "work", "recovery", "work", "cooldown"])
        XCTAssertEqual(series.spans.map(\.start), [0, 5, 9, 12, 16])
        XCTAssertEqual(series.spans.map(\.end), [5, 9, 12, 16, 76])
        XCTAssertEqual(series.spans.map(\.workNumber), [0, 1, 0, 2, 0])
        XCTAssertEqual(entry.endedEarly, false)
    }

    func testPartialCatchUpKeepsCrossedSpansBeforeEarlyFinish() throws {
        let vm = recoveryViewModel(warmup: 5, count: 2)
        let start = Date()
        defer { vm.workoutLogEntries.forEach { HeartRateSeriesStore.delete(for: $0.id) }; vm.reset() }
        vm.startTimer(now: start)
        vm.reconcileTimerState(now: start + 10, playAlarm: false)
        XCTAssertEqual(vm.currentIntervalIndex, 2)
        XCTAssertEqual(vm.timeRemaining, 2, accuracy: 0.001)
        vm.finishAndSaveWorkout(now: start + 10)
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        XCTAssertEqual(HeartRateSeriesStore.load(for: id)?.spans.map(\.kind), ["warmup", "work", "recovery"])
        XCTAssertEqual(HeartRateSeriesStore.load(for: id)?.spans.map(\.end), [5, 9, 10])
    }

    func testReviewEditsPersistImmediatelyWithoutDoneOrDismissal() throws {
        let vm = recoveryViewModel()
        let start = Date()
        defer { vm.workoutLogEntries.forEach { HeartRateSeriesStore.delete(for: $0.id) }; vm.reset() }
        vm.unitPreference = .metric
        vm.startTimer(now: start)
        vm.finishAndSaveWorkout(now: start + 2)
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        vm.workoutNotesDraft = "Keep this even if the app closes"
        vm.performanceDraft[0] = 12
        vm.performanceNotesDraft[0] = "Incline 3%"
        let entry = try XCTUnwrap(TimerViewModel().workoutLogEntries.first)
        XCTAssertEqual(entry.notes, "Keep this even if the app closes")
        XCTAssertEqual(entry.workoutType, .treadmill)
        XCTAssertEqual(entry.intervalPerformances?.first?.primary, 12)
        XCTAssertEqual(entry.intervalPerformances?.first?.note, "Incline 3%")
        vm.preparePerformanceDraft() // A repeated sheet appearance must not erase edits.
        XCTAssertEqual(vm.performanceDraft[0], 12)
    }

    func testReviewDoesNotAutosavePerformanceCopiedFromPreviousWorkout() {
        let vm = recoveryViewModel()
        vm.workoutLogEntries = [.init(workoutType: .treadmill, notes: "", modality: .treadmill,
                                     intervalPerformances: [.init(intervalNumber: 1, primary: 14)])]
        vm.persistWorkoutLogEntries()
        vm.finishWorkout()
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        XCTAssertEqual(vm.performanceDraft.count, 1)
        XCTAssertNil(vm.performanceDraft[0])
        XCTAssertNil(vm.workoutLogEntries.first?.intervalPerformances)
        vm.reset()
    }

    func testFailedSeriesSaveKeepsCheckpointAndRetriesAfterRelaunchWithoutDuplicate() throws {
        let vm = recoveryViewModel(seriesSaver: { _, _ in false })
        let start = Date()
        vm.startTimer(now: start)
        vm.finishAndSaveWorkout(now: start + 2)
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        XCTAssertTrue(vm.hasPendingWorkoutSave)
        XCTAssertFalse(vm.completeWorkoutReview())
        XCTAssertNotNil(vm.workoutSaveError)
        XCTAssertTrue(FileManager.default.fileExists(atPath: TimerViewModel.defaultCheckpointURL.path))
        let restored = TimerViewModel()
        defer { restored.reset(); HeartRateSeriesStore.delete(for: id) }
        XCTAssertFalse(restored.hasPendingWorkoutSave)
        XCTAssertEqual(restored.workoutLogEntries.map(\.id), [id])
        XCTAssertNotNil(HeartRateSeriesStore.load(for: id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: TimerViewModel.defaultCheckpointURL.path))
    }

    func testExplicitDeleteOfFailedSaveCannotRestoreFromCheckpoint() throws {
        let vm = recoveryViewModel(seriesSaver: { _, _ in false })
        vm.startTimer()
        vm.finishAndSaveWorkout()
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        vm.deleteCurrentWorkoutAndResetSession()
        let restored = TimerViewModel()
        XCTAssertFalse(restored.workoutLogEntries.contains { $0.id == id })
        XCTAssertNil(restored.workoutStartDate)
        XCTAssertFalse(restored.showPostWorkoutSummary)
    }

    func testLateWatchFinishOrDiscardNeverDeletesCompletedOrNewerWorkout() throws {
        let vm = recoveryViewModel()
        let start = Date()
        defer { vm.workoutLogEntries.forEach { HeartRateSeriesStore.delete(for: $0.id) }; vm.reset() }
        vm.startTimer(now: start)
        let first = try XCTUnwrap(vm.activeWorkoutID)
        vm.finishAndSaveWorkout(now: start + 2)
        vm.handleWorkoutCommand(WatchMessageKey.cmdFinish, workoutID: first)
        vm.handleWorkoutCommand(WatchMessageKey.cmdDiscard, workoutID: first)
        XCTAssertEqual(vm.workoutLogEntries.map(\.id), [first])
        vm.completeWorkoutReview()
        vm.startTimer()
        let second = vm.activeWorkoutID
        vm.handleWorkoutCommand(WatchMessageKey.cmdDiscard, workoutID: first)
        vm.handleWorkoutCommand(WatchMessageKey.cmdFinish, workoutID: first)
        vm.handleWorkoutCommand(WatchMessageKey.cmdReset, workoutID: first)
        vm.finishAndSaveWorkout(for: first)
        vm.discardActiveWorkout(for: first)
        XCTAssertEqual(vm.activeWorkoutID, second)
        XCTAssertTrue(vm.isRunning)
        vm.handleWorkoutCommand(WatchMessageKey.cmdDeleteCompleted, workoutID: first)
        XCTAssertTrue(vm.workoutLogEntries.isEmpty)
        XCTAssertEqual(vm.activeWorkoutID, second)
        XCTAssertTrue(vm.isRunning)
        HeartRateSeriesStore.delete(for: first)
    }

    func testMalformedHistoryFieldDoesNotDowngradeOtherDetailsOrRows() throws {
        let first = WorkoutLogEntry(workoutType: .treadmill, notes: "Keep notes",
                                    sessionBreakdown: .init(totalDuration: 240, warmupDuration: 0, highIntensityDuration: 240, recoveryDuration: 0, cooldownDuration: 0, cooldownSkipped: false),
                                    modality: .treadmill, intervalPerformances: [.init(intervalNumber: 1, primary: 12)])
        let second = WorkoutLogEntry(completedAt: Date(timeIntervalSince1970: 1_800_000_000), workoutType: .rowing, notes: "Other row", modality: .rowing)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode([first, second])) as? [[String: Any]])
        rows[0]["hrSummary"] = "invalid"
        rows.append(["completedAt": "not a date"])
        let raw = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        UserDefaults.standard.set(raw, forKey: "workoutLogEntriesData")
        let vm = TimerViewModel()
        XCTAssertEqual(vm.workoutLogEntries.count, 2)
        let recovered = try XCTUnwrap(vm.workoutLogEntries.first { $0.id == first.id })
        XCTAssertEqual(recovered.sessionBreakdown, first.sessionBreakdown)
        XCTAssertEqual(recovered.intervalPerformances, first.intervalPerformances)
        XCTAssertEqual(recovered.notes, first.notes)
        XCTAssertEqual(vm.workoutLogEntries.first { $0.id == second.id }, second)
        let directory = TimerViewModel.defaultCheckpointURL.deletingLastPathComponent().appendingPathComponent("Recovery")
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(try backups.contains { try String(contentsOf: $0, encoding: .utf8) == raw })
    }

    func testUnreadableHistoryIsPreservedBeforeAnyNewSave() throws {
        let raw = "{ broken workout history"
        UserDefaults.standard.set(raw, forKey: "workoutLogEntriesData")
        let vm = recoveryViewModel()
        vm.finishWorkout()
        XCTAssertEqual(TimerViewModel().workoutLogEntries.count, 1)
        let directory = TimerViewModel.defaultCheckpointURL.deletingLastPathComponent().appendingPathComponent("Recovery")
        let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertTrue(try backups.contains { try String(contentsOf: $0, encoding: .utf8) == raw })
        vm.reset()
    }

    func testHistoryCannotOverwriteDamagedStorageWhenBackupFails() throws {
        let blocker = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("not a directory".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let raw = "{ broken but must be kept"
        UserDefaults.standard.set(raw, forKey: "workoutLogEntriesData")
        let vm = TimerViewModel(checkpointURL: blocker.appendingPathComponent("current.json"))
        vm.finishWorkout()
        XCTAssertEqual(UserDefaults.standard.string(forKey: "workoutLogEntriesData"), raw)
        XCTAssertTrue(vm.hasPendingWorkoutSave)
        XCTAssertNotNil(vm.workoutSaveError)
    }
}

extension N4x4Tests {
    func testChangingReviewTypeClearsOldMetricBeforeAutosavingNewType() throws {
        let vm = recoveryViewModel()
        vm.finishWorkout()
        vm.selectedWorkoutType = .treadmill
        vm.performanceDraft[0] = 12
        vm.selectedWorkoutType = .rowing
        let row = try XCTUnwrap(TimerViewModel().workoutLogEntries.first)
        XCTAssertEqual(row.workoutType, .rowing)
        XCTAssertNil(row.intervalPerformances, "Speed cannot become a rowing stroke rate")
        vm.reset()
    }

    func testWorkoutExportUsesLatestReviewEditsAndRejectsDeletedWorkout() throws {
        let vm = recoveryViewModel()
        let start = Date()
        vm.startTimer(now: start)
        vm.finishAndSaveWorkout(now: start + 2)
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        defer { HeartRateSeriesStore.delete(for: id); vm.reset() }
        vm.selectedWorkoutType = .treadmill
        vm.preparePerformanceDraft()
        vm.unitPreference = .imperial
        vm.workoutNotesDraft = "Updated after opening summary"
        vm.performanceDraft[0] = 12.5
        vm.performanceNotesDraft[0] = "Incline 3%"
        // No Done tap is needed and a nil view recording uses completed memory.
        let file = try XCTUnwrap(vm.workoutExport(for: id, series: nil))
        XCTAssertEqual(file.entry.notes, "Updated after opening summary")
        XCTAssertEqual(file.entry.intervalPerformances?.first?.primary, PerformanceUnits.mphToKmh(12.5))
        XCTAssertEqual(file.entry.intervalPerformances?.first?.note, "Incline 3%")
        XCTAssertEqual(file.series, vm.completedSeries)
        XCTAssertNotNil(file.series)
        let count = vm.workoutLogEntries.count
        _ = try WorkoutExport(entry: file.entry, series: file.series).jsonData()
        XCTAssertEqual(vm.workoutLogEntries.count, count, "Export must not insert a workout")
        vm.deleteWorkoutLogEntry(id: id)
        XCTAssertNil(vm.workoutExport(for: id, series: file.series))
    }

    func testDamagedCheckpointIsPreservedWithoutBlockingANewWorkout() throws {
        let url = TimerViewModel.defaultCheckpointURL
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let bad = Data("{ invalid checkpoint".utf8)
        try bad.write(to: url)
        let vm = recoveryViewModel()
        XCTAssertNil(vm.workoutStartDate)
        XCTAssertNotNil(vm.historyRecoveryNotice)
        vm.startTimer()
        XCTAssertNotNil(vm.activeWorkoutID)
        let backups = try FileManager.default.contentsOfDirectory(at: url.deletingLastPathComponent().appendingPathComponent("Recovery"), includingPropertiesForKeys: nil)
        XCTAssertTrue(try backups.contains { try Data(contentsOf: $0) == bad })
        vm.reset()
    }

    func testDeletedWorkoutDoesNotReturnFromAnOlderLogOrCheckpoint() throws {
        let vm = recoveryViewModel(seriesSaver: { _, _ in false })
        vm.startTimer()
        vm.finishAndSaveWorkout()
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        let oldCheckpoint = try Data(contentsOf: TimerViewModel.defaultCheckpointURL)
        let oldLog = UserDefaults.standard.string(forKey: "workoutLogEntriesData")
        vm.deleteCurrentWorkoutAndResetSession()
        try oldCheckpoint.write(to: TimerViewModel.defaultCheckpointURL)
        UserDefaults.standard.set(oldLog, forKey: "workoutLogEntriesData")
        let restored = TimerViewModel()
        XCTAssertFalse(restored.workoutLogEntries.contains { $0.id == id })
        XCTAssertNil(restored.workoutStartDate)
        XCTAssertFalse(restored.showPostWorkoutSummary)
    }

    func testIdleOrAlreadyCompletedSkipCannotCreateAnotherWorkout() {
        let vm = recoveryViewModel()
        vm.skip()
        XCTAssertTrue(vm.workoutLogEntries.isEmpty)
        vm.startTimer()
        vm.finishAndSaveWorkout()
        let id = vm.completedWorkoutEntryID
        defer { if let id { HeartRateSeriesStore.delete(for: id) }; vm.reset() }
        vm.skip()
        XCTAssertEqual(vm.workoutLogEntries.map(\.id), id.map { [$0] } ?? [])
    }
}

extension N4x4Tests {
    func testRecoveryReplaysNewerReviewEditsEvenIfOlderLogAndSeriesExist() throws {
        let vm = recoveryViewModel(seriesSaver: { series, id in
            _ = HeartRateSeriesStore.save(series, for: id)
            return false // Leave a checkpoint as if the final save acknowledgement failed.
        })
        vm.startTimer()
        vm.finishAndSaveWorkout()
        let id = try XCTUnwrap(vm.completedWorkoutEntryID)
        let olderLog = UserDefaults.standard.string(forKey: "workoutLogEntriesData")
        vm.workoutNotesDraft = "Newer checkpoint notes"
        UserDefaults.standard.set(olderLog, forKey: "workoutLogEntriesData")
        let restored = TimerViewModel()
        defer { restored.reset(); HeartRateSeriesStore.delete(for: id) }
        XCTAssertEqual(restored.workoutLogEntries.count, 1)
        XCTAssertEqual(restored.workoutLogEntries.first?.notes, "Newer checkpoint notes")
        XCTAssertFalse(restored.hasPendingWorkoutSave)
    }
}

extension N4x4Tests {
    func testLiveActivityCanRenderExpiredCountdownWithoutInvalidDateRange() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let state = N4x4LiveActivityAttributes.ContentState(
            intervalName: "Work", phase: .highIntensity, intervalEndTime: end,
            isRunning: true, currentInterval: 1, totalIntervals: 4, hrLow: 140, hrHigh: 170)
        let expired = state.countdownRange(at: end + 10)
        XCTAssertEqual(expired.lowerBound, end + 10)
        XCTAssertEqual(expired.upperBound, end + 10)
        XCTAssertEqual(state.countdownRange(at: end), end...end)
        XCTAssertEqual(state.countdownRange(at: end - 10), (end - 10)...end)
    }
}

final class WorkoutEnhancementTests: XCTestCase {
    override func setUp() {
        super.setUp()
        for key in ["workoutLogEntriesData", "discardedPhoneWorkoutIDs", "bonusRoundEnabled", "appleSensorHREnabled"] {
            UserDefaults.standard.removeObject(forKey: key)
        }
        UserDefaults.standard.set(false, forKey: "healthKitEnabled")
        UserDefaults.standard.set(true, forKey: "healthKitUserOptedOut")
        UserDefaults.standard.set(false, forKey: "workoutRemindersEnabled")
    }

    private func fixture() -> (WorkoutLogEntry, HeartRateSeries, [WorkoutEnergyReport]) {
        let start = Date(timeIntervalSince1970: 1_790_000_000.125)
        var timing = WorkoutActivityTiming(startedAt: start)
        timing.pause(at: start + 30)
        timing.resume(at: start + 60)
        timing.finish(at: start + 90)
        let series = HeartRateSeries(samples: [0.0, 12, 28, 62, 80, 90].enumerated().map {
            .init(t: $0.element, bpm: Double(120 + $0.offset * 10))
        }, spans: [.init(kind: "warmup", workNumber: 0, start: 0, end: 10, targetLo: 0, targetHi: 0),
                    .init(kind: "work", workNumber: 1, start: 10, end: 75, targetLo: 150, targetHi: 170),
                    .init(kind: "cooldown", workNumber: 0, start: 75, end: 90, targetLo: 0, targetHi: 0)],
            startedAt: start, activityTiming: timing)
        let row = WorkoutLogEntry(completedAt: start + 90, workoutType: .treadmill, notes: "Private note",
            sessionBreakdown: .init(totalDuration: 60, warmupDuration: 10, highIntensityDuration: 35,
                                    recoveryDuration: 0, cooldownDuration: 15, cooldownSkipped: false), customTitle: "Fjord intervals — 4×4")
        let samples: [WorkoutEnergySample] = [(0.0, 10.0, 2.0), (10, 28, 7), (32, 58, 100), (60, 90, 10)].map {
            .init(id: UUID(), start: start.timeIntervalSince1970 + $0.0,
                  end: start.timeIntervalSince1970 + $0.1, kilocalories: $0.2)
        }
        let report = WorkoutEnergyReport(id: UUID(), workoutID: row.id, start: start.timeIntervalSince1970,
            end: (start + 90).timeIntervalSince1970, samples: samples, finalized: true)
        return (row, series, [report])
    }

    func testFITPreservesTimingHeartRateLapsCaloriesAndOriginalIdentity() throws {
        let (row, series, energy) = fixture()
        let export = WorkoutFITExport(entry: row, series: series, energyReports: energy)
        let data = try export.data()
        XCTAssertTrue(export.isAvailable)
        XCTAssertEqual(String(decoding: data[8..<12], as: UTF8.self), ".FIT")
        XCTAssertEqual(data.count, Int(data[4..<8].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }) + 16)
        var crc: UInt16 = 0
        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 { crc = crc & 1 == 1 ? (crc >> 1) ^ 0xA001 : crc >> 1 }
        }
        XCTAssertEqual(crc, 0)
        XCTAssertEqual(data, try export.data(), "Re-exporting the same snapshot must keep stable FIT identity")
        XCTAssertNotNil(data.range(of: Data(row.displayTitle.utf8)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("N4x4-validation-paused.fit")
        try data.write(to: url)
        print("FIT validation fixture: \(url.path)")
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.data")
        attachment.name = "N4x4-validation-paused.fit"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFITWithoutHeartRateKeepsKnownTimingAndDoesNotInventLegacyDates() throws {
        let (row, series, _) = fixture()
        var export = HealthWorkoutExport(start: series.startedAt, end: row.completedAt, requested: false,
            timing: series.activityTiming, activeDuration: 60)
        export.workoutTypeRaw = row.workoutType.rawValue
        let timed = WorkoutLogEntry(id: row.id, completedAt: row.completedAt, workoutType: .cycle,
                                    notes: "", healthExport: export)
        let file = WorkoutFITExport(entry: timed, series: nil)
        XCTAssertTrue(file.isAvailable)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("N4x4-validation-no-hr.fit")
        try file.data().write(to: url)
        print("FIT validation fixture: \(url.path)")
        let attachment = XCTAttachment(data: try file.data(), uniformTypeIdentifier: "public.data")
        attachment.name = "N4x4-validation-no-hr.fit"
        attachment.lifetime = .keepAlways
        add(attachment)
        let legacy = WorkoutLogEntry(workoutType: .other, notes: "", sessionBreakdown: .init(totalDuration: 600,
            warmupDuration: 0, highIntensityDuration: 600, recoveryDuration: 0, cooldownDuration: 0, cooldownSkipped: false))
        XCTAssertFalse(WorkoutFITExport(entry: legacy, series: nil).isAvailable)
        XCTAssertNil(WorkoutExportFile(entry: legacy, series: nil).fitFile)
        XCTAssertThrowsError(try WorkoutFITExport(entry: legacy, series: nil).data())
    }

    func testFITRejectsNonFiniteAndOutOfRangeTimeline() {
        let (row, series, _) = fixture()
        let broken = HeartRateSeries(samples: [], spans: [], startedAt: Date(timeIntervalSince1970: .nan))
        XCTAssertFalse(WorkoutFITExport(entry: row, series: broken).isAvailable)
        let ancient = HeartRateSeries(samples: [], spans: [], startedAt: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(WorkoutFITExport(entry: row, series: ancient).isAvailable)
        XCTAssertTrue(WorkoutExportFile(entry: row, series: series).fitFile?.filename.hasSuffix(".fit") == true)
    }

    @MainActor
    private func model(checkpoint: URL? = nil) -> TimerViewModel {
        let vm = TimerViewModel(checkpointURL: checkpoint ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json"), seriesSaver: { _, _ in true })
        vm.healthKitEnabled = false
        vm.audioMode = .silent
        vm.hapticsEnabled = false
        vm.notificationsEnabled = false
        vm.liveActivitiesEnabled = false
        return vm
    }

    @MainActor
    private func start(_ vm: TimerViewModel, at date: Date) {
        vm.numberOfIntervals = 2
        vm.warmupDuration = 0
        vm.highIntensityDuration = 10
        vm.restDuration = 5
        vm.cooldownEnabled = true
        vm.cooldownDuration = 5
        vm.startTimer(now: date)
    }

    @MainActor
    func testBonusIsOptInAndOnlyQueuesOnceDuringLastWorkInterval() {
        let vm = model(), date = Date()
        start(vm, at: date)
        XCTAssertFalse(vm.bonusRoundEnabled)
        vm.bonusRoundEnabled = true
        XCTAssertFalse(vm.canAddBonusRound)
        vm.reconcileTimerState(now: date + 16, playAlarm: false)
        XCTAssertTrue(vm.canAddBonusRound)
        let deadline = vm.intervalEndTime
        vm.addBonusRound(now: date + 17)
        XCTAssertEqual(vm.sessionIntervalCount, 3)
        XCTAssertEqual(vm.numberOfIntervals, 2, "The next workout's settings must stay unchanged")
        XCTAssertEqual(vm.intervalEndTime, deadline)
        XCTAssertTrue(vm.canUndoBonusRound)
        XCTAssertFalse(vm.canAddBonusRound)
        vm.addBonusRound(now: date + 18)
        XCTAssertEqual(vm.sessionIntervalCount, 3)
        vm.undoBonusRound(now: date + 19)
        XCTAssertEqual(vm.sessionIntervalCount, 2)
        XCTAssertEqual(vm.intervalEndTime, deadline)
        vm.reset()
    }

    @MainActor
    func testBonusQueuedWhilePausedUsesSessionDurationsAndKeepsPause() {
        let vm = model(), date = Date()
        start(vm, at: date)
        vm.bonusRoundEnabled = true
        vm.pause(now: date + 17)
        let remaining = vm.timeRemaining
        vm.highIntensityDuration = 240
        vm.restDuration = 180
        vm.addBonusRound(now: date + 200)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.timeRemaining, remaining)
        XCTAssertEqual(vm.intervals[3].duration, 5)
        XCTAssertEqual(vm.intervals[4].duration, 10)
        vm.reset()
    }

    @MainActor
    func testBonusBoundaryAndStaleCommandsCannotExtendAnotherPhaseOrSession() {
        let vm = model(), date = Date()
        start(vm, at: date)
        vm.bonusRoundEnabled = true
        vm.addBonusRound(for: UUID(), now: date + 16)
        XCTAssertEqual(vm.sessionIntervalCount, 2)
        vm.addBonusRound(now: date + 25) // Tap arrives exactly as the final work interval ends.
        XCTAssertEqual(vm.currentIntervalType, .cooldown)
        XCTAssertEqual(vm.sessionIntervalCount, 2)
        vm.reset()
    }

    @MainActor
    func testCancellingBonusAfterCoreCompletionDoesNotLoseCompletedWorkout() {
        let vm = model(), date = Date()
        start(vm, at: date)
        vm.bonusRoundEnabled = true
        vm.addBonusRound(now: date + 16)
        vm.finishAndSaveWorkout(now: date + 26)
        XCTAssertFalse(vm.sessionEndedEarly)
        XCTAssertTrue(vm.workoutLogEntries.first?.countsTowardStreak == true)
        XCTAssertEqual(vm.workoutLogEntries.first?.bonusRounds, 0)
        vm.reset()
    }

    @MainActor
    func testFinishedBonusIsRecordedAndNamedWithoutSecondWorkout() {
        let vm = model(), date = Date()
        start(vm, at: date)
        vm.bonusRoundEnabled = true
        vm.addBonusRound(now: date + 16)
        vm.reconcileTimerState(now: date + 100, playAlarm: false)
        XCTAssertEqual(vm.workoutLogEntries.count, 1)
        XCTAssertEqual(vm.workoutLogEntries.first?.bonusRounds, 1)
        XCTAssertEqual(vm.completedSeries?.spans.filter { $0.kind == "work" }.count, 3)
        XCTAssertTrue(vm.workoutLogEntries.first?.displayTitle.contains("+ bonus") == true)
        XCTAssertFalse(vm.sessionEndedEarly)
        vm.reset()
    }

    @MainActor
    func testBonusCheckpointRestoresExtensionAndOriginalCompletionThreshold() {
        let checkpoint = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("current.json")
        defer { try? FileManager.default.removeItem(at: checkpoint.deletingLastPathComponent()) }
        let vm = model(checkpoint: checkpoint), date = Date()
        start(vm, at: date)
        vm.bonusRoundEnabled = true
        vm.addBonusRound(now: date + 16)
        vm.pause(now: date + 17)
        let restored = model(checkpoint: checkpoint)
        XCTAssertEqual(restored.sessionIntervalCount, 3)
        XCTAssertEqual(restored.bonusInsertionIndex, 3)
        XCTAssertTrue(restored.canUndoBonusRound)
        restored.startTimer(now: date + 100)
        restored.finishAndSaveWorkout(now: date + 109) // Eight work seconds, then one recovery second.
        XCTAssertFalse(restored.sessionEndedEarly)
        restored.reset()
        vm.reset()
    }

    @MainActor
    func testCustomNamePersistsWithoutChangingSavedHealthIntent() throws {
        let vm = model(), date = Date()
        var health = HealthWorkoutExport(start: date - 600, end: date, requested: true)
        health.workoutTitle = "Original Health title"
        health.workoutTypeRaw = WorkoutType.cycle.rawValue
        health.state = .saved
        let row = WorkoutLogEntry(completedAt: date, workoutType: .cycle, notes: "", healthExport: health)
        vm.workoutLogEntries = [row]
        vm.updateWorkoutTitle("Hill session", for: row.id)
        XCTAssertEqual(vm.workoutLogEntries.first?.displayTitle, "Hill session")
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport, health)
        XCTAssertEqual(vm.workoutExport(for: row.id, series: nil)?.entry.displayTitle, "Hill session")
        let restored = model()
        XCTAssertEqual(restored.workoutLogEntries.first?.customTitle, "Hill session")
        vm.updateWorkoutTitle("  ", for: row.id)
        XCTAssertEqual(vm.workoutLogEntries.first?.displayTitle, "Norwegian 4×4 — Cycle")
    }

    func testStandaloneBonusRoundPersistsAndDoesNotPenalizeCoreCompletion() throws {
        var plan = WatchWorkoutPlan.fallback
        plan.steps = [.init(phase: .highIntensity, duration: 10), .init(phase: .rest, duration: 5),
                      .init(phase: .highIntensity, duration: 10), .init(phase: .cooldown, duration: 5)]
        plan.totalIntervals = 2
        plan.bonusRoundEnabled = true
        let date = Date()
        var engine = try XCTUnwrap(WatchWorkoutEngine.start(plan: plan, now: date))
        engine.addBonusRound(now: date + 16)
        XCTAssertEqual(engine.plan.totalIntervals, 3)
        var restored = try JSONDecoder().decode(WatchWorkoutEngine.self, from: JSONEncoder().encode(engine))
        restored.finish(now: date + 26)
        XCTAssertEqual(restored.completedRecord()?.endedEarly, false)
        XCTAssertEqual(restored.completedRecord()?.bonusRounds, 0)
        engine.reconcile(now: date + 45)
        XCTAssertEqual(engine.completedRecord()?.bonusRounds, 1)
        XCTAssertEqual(engine.completedRecord()?.endedEarly, false)
    }

    func testStandaloneBonusUndoAndDisabledLegacyPlan() throws {
        var plan = WatchWorkoutPlan.fallback
        plan.steps = [.init(phase: .highIntensity, duration: 10)]
        plan.totalIntervals = 1
        let date = Date()
        var engine = try XCTUnwrap(WatchWorkoutEngine.start(plan: plan, now: date))
        engine.addBonusRound(now: date + 1)
        XCTAssertEqual(engine.plan.steps.count, 1)
        plan.bonusRoundEnabled = true
        plan.bonusRecoveryDuration = 5
        engine = try XCTUnwrap(WatchWorkoutEngine.start(plan: plan, now: date))
        engine.pause(now: date + 2)
        engine.addBonusRound(now: date + 3)
        XCTAssertFalse(engine.isRunning)
        XCTAssertEqual(engine.plan.steps.map(\.duration), [10, 5, 10])
        engine.undoBonusRound(now: date + 4)
        XCTAssertEqual(engine.plan.steps.count, 1)
        engine.resume(now: date + 100)
        engine.reconcile(now: date + 108)
        XCTAssertEqual(engine.completedRecord()?.endedEarly, false)
    }
}

extension WorkoutEnhancementTests {
    @MainActor
    func testBonusWorkCannotTurnSkippedOriginalWorkIntoFullCompletion() {
        let vm = model(), date = Date()
        start(vm, at: date)
        vm.bonusRoundEnabled = true
        vm.skip(now: date + 5) // Five of the first ten work seconds were skipped.
        vm.reconcileTimerState(now: date + 11, playAlarm: false)
        vm.addBonusRound(now: date + 12)
        vm.reconcileTimerState(now: date + 200, playAlarm: false)
        XCTAssertTrue(vm.sessionEndedEarly, "Bonus work must not hide skipped original intervals")
        vm.reset()
    }

    @MainActor
    func testHealthNameAndActivityAreFrozenWhenReviewChanges() throws {
        let vm = model(), date = Date()
        vm.setDefaultWorkoutType(.treadmill)
        start(vm, at: date)
        vm.finishAndSaveWorkout(now: date + 5)
        let original = try XCTUnwrap(vm.workoutLogEntries.first?.healthExport)
        XCTAssertEqual(original.workoutTypeRaw, WorkoutType.treadmill.rawValue)
        XCTAssertEqual(original.workoutTitle, "Norwegian 4×4 — Treadmill")
        vm.workoutTitleDraft = "Hill session"
        vm.selectedWorkoutType = .cycle
        XCTAssertEqual(vm.workoutLogEntries.first?.displayTitle, "Hill session")
        XCTAssertEqual(vm.workoutLogEntries.first?.healthExport, original)
        XCTAssertEqual(WorkoutType.treadmill.healthActivityType, .running)
        XCTAssertEqual(WorkoutType.cycle.healthActivityType, .cycling)
        XCTAssertEqual(WorkoutType.elliptical.healthActivityType, .elliptical)
        vm.reset()
    }
}

final class SpeechVoiceSettingsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: SpeechManager.voicePreferenceKey)
        UserDefaults.standard.set(false, forKey: "healthKitEnabled")
        UserDefaults.standard.set(true, forKey: "healthKitUserOptedOut")
        UserDefaults.standard.set(false, forKey: "workoutRemindersEnabled")
    }
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SpeechManager.voicePreferenceKey)
        super.tearDown()
    }

    @MainActor
    func testDefaultVoiceAndMissingVoiceUseTheExistingEnglishLookup() {
        let vm = TimerViewModel(checkpointURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        XCTAssertEqual(vm.speechVoiceIdentifier, "")
        XCTAssertEqual(SpeechManager.voice(identifier: "")?.identifier,
                       AVSpeechSynthesisVoice(language: "en-US")?.identifier)
        XCTAssertEqual(SpeechManager.voice(identifier: "com.apple.unavailable.n4x4-test")?.identifier,
                       SpeechManager.voice(identifier: "")?.identifier)
        vm.reset()
    }

    @MainActor
    func testChosenVoicePersistsAndInventoryRefreshDoesNotReplaceIt() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let vm = TimerViewModel(checkpointURL: url)
        let voice = SpeechVoiceOption(id: "com.apple.test.english", name: "Example", language: "en-GB", quality: .premium)
        vm.refreshSpeechVoiceOptions(options: [voice])
        XCTAssertEqual(vm.speechVoiceIdentifier, "", "Installing premium voices must not change the default")
        vm.speechVoiceIdentifier = voice.id
        XCTAssertFalse(vm.selectedSpeechVoiceUnavailable)
        vm.refreshSpeechVoiceOptions(options: [])
        XCTAssertTrue(vm.selectedSpeechVoiceUnavailable)
        XCTAssertEqual(vm.speechVoiceIdentifier, voice.id)
        let restored = TimerViewModel(checkpointURL: url)
        XCTAssertEqual(restored.speechVoiceIdentifier, voice.id)
        restored.refreshSpeechVoiceOptions(options: [voice])
        XCTAssertFalse(restored.selectedSpeechVoiceUnavailable)
        restored.speechVoiceIdentifier = ""
        XCTAssertFalse(restored.selectedSpeechVoiceUnavailable)
        vm.reset()
        restored.reset()
    }

    func testInstalledSelectionResolvesTheChosenAppleEnglishVoice() throws {
        guard let option = SpeechVoiceOption.installed().first else { throw XCTSkip("No English voice is exposed by this simulator") }
        XCTAssertEqual(SpeechManager.voice(identifier: option.id)?.identifier, option.id)
        XCTAssertTrue(option.label.contains(option.name))
        XCTAssertTrue(SpeechVoiceOption.installed().allSatisfy { $0.id.hasPrefix("com.apple.") && $0.language.hasPrefix("en") })
    }

    func testLatePreviewCallbacksCannotFinishNewWorkoutCues() {
        let preview = NSObject(), cue = NSObject()
        var state = SpeechPlaybackState()
        state.begin(preview, preview: true)
        state.begin(cue, preview: false)
        XCTAssertFalse(state.finish(preview))
        XCTAssertNil(state.consumePreviewStop(), "Leaving Audio settings must not stop the new cue")
        XCTAssertTrue(state.finish(cue))
        XCTAssertFalse(state.finish(cue), "Duplicate callbacks must not restore the session twice")
    }

    func testClosingPreviewThenStartingCueKeepsLateCancellationBoundToPreview() {
        let preview = NSObject(), cue = NSObject()
        var state = SpeechPlaybackState()
        state.begin(preview, preview: true)
        XCTAssertNotNil(state.consumePreviewStop())
        XCTAssertNil(state.consumePreviewStop())
        state.begin(cue, preview: false)
        XCTAssertFalse(state.finish(preview))
        XCTAssertTrue(state.finish(cue))
    }
}
