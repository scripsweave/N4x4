import XCTest
@testable import N4x4

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
            "healthKitEnabled",
            "hasCompletedOnboarding"
        ].forEach { defaults.removeObject(forKey: $0) }
    }

    func testSetupIntervalsIncludesWarmupAndCorrectPattern() {
        let vm = TimerViewModel()
        vm.numberOfIntervals = 3
        vm.warmupDuration = 120
        vm.highIntensityDuration = 240
        vm.restDuration = 180
        vm.setupIntervals()

        XCTAssertEqual(vm.intervals.count, 6)
        XCTAssertEqual(vm.intervals[0].type, .warmup)
        XCTAssertEqual(vm.intervals[1].type, .highIntensity)
        XCTAssertEqual(vm.intervals[2].type, .rest)
        XCTAssertEqual(vm.intervals[3].type, .highIntensity)
        XCTAssertEqual(vm.intervals[4].type, .rest)
        XCTAssertEqual(vm.intervals[5].type, .highIntensity)
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

        XCTAssertTrue(vm.showCompletionMessage)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.timeRemaining, 0)
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

    func testOnboardingFlowMovesForwardAndBackWithinBounds() {
        let flow = OnboardingFlowViewModel()

        XCTAssertEqual(flow.currentStep, .welcome)

        flow.next()
        XCTAssertEqual(flow.currentStep, .structure)

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
}
