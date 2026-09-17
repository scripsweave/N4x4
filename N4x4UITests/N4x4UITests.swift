//
//  N4x4UITests.swift
//  N4x4UITests
//
//  Created by Jan van Rensburg on 9/12/24.
//

import XCTest

final class N4x4UITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }

    private var reviewLaunchArguments: [String] {
        ["-hasCompletedOnboarding", "YES",
         "-hasSeenHRSourcesAnnouncement", "YES",
         "-hasSeenWatchUpgradePrompt", "YES",
         "-healthKitEnabled", "NO", "-healthKitUserOptedOut", "YES",
         "-workoutRemindersEnabled", "NO", "-notificationsEnabled", "NO",
         "-audioModeRaw", "Silent", "-hapticsEnabled", "NO",
         "-shownMilestonesData", "\"[1,5,10,25,50,100]\"",
         "-hasRequestedAppReview", "YES"]
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        print(app.debugDescription)
        XCTAssertTrue(element.isHittable)
    }

    func testCompletedWorkoutSurvivesRelaunchWithoutDoneAndCanBeDeleted() throws {
        let app = XCUIApplication()
        let timerArguments = ["-numberOfIntervals", "1", "-warmupDuration", "0",
                              "-highIntensityDuration", "1", "-cooldownEnabled", "NO"]
        app.launchArguments = reviewLaunchArguments + timerArguments + ["-workoutLogEntriesData", "\"[]\""]
        app.launch()
        let start = app.buttons["START"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        let summaryScreenshot = XCTAttachment(screenshot: app.screenshot())
        summaryScreenshot.name = "Automatically saved summary"
        summaryScreenshot.lifetime = .keepAlways
        add(summaryScreenshot)

        // The client must not have to tap Done to retain the finished workout.
        app.terminate()
        app.launchArguments = reviewLaunchArguments + timerArguments
        app.launch()
        app.tabBars.buttons["History"].tap()
        let workouts = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workout-"))
        reveal(workouts.firstMatch, in: app)
        XCTAssertEqual(workouts.count, 1)
        workouts.firstMatch.tap()
        let delete = app.navigationBars.buttons["Delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        app.alerts["Delete workout?"].buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Completed workouts are saved here automatically."].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        app.tabBars.buttons["History"].tap()
        reveal(app.staticTexts["Completed workouts are saved here automatically."], in: app)
        XCTAssertEqual(workouts.count, 0)

        // Done must also lead to a usable History sheet and nested detail.
        app.tabBars.buttons["Home"].tap()
        app.buttons["START"].tap()
        XCTAssertTrue(app.staticTexts["Saved to History"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Done"].tap()
        XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
        reveal(workouts.firstMatch, in: app)
        workouts.firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Delete"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Delete"].tap()
        app.alerts["Delete workout?"].buttons["Delete"].tap()
        XCTAssertTrue(app.staticTexts["Completed workouts are saved here automatically."].waitForExistence(timeout: 5))
    }

    func testHistoryListsBothSameDayWorkoutsAndDeletesOnlySelectedSession() throws {
        let app = XCUIApplication()
        let firstID = "11111111-1111-1111-1111-111111111111"
        let secondID = "22222222-2222-2222-2222-222222222222"
        let date = ISO8601DateFormatter().string(from: Date())
        let rows: [[String: Any]] = [
            ["id": firstID, "completedAt": date, "workoutType": "Run", "notes": "First workout"],
            ["id": secondID, "completedAt": date, "workoutType": "Cycle", "notes": "Second workout"]
        ]
        let json = String(decoding: try JSONSerialization.data(withJSONObject: rows), as: UTF8.self)
        // NSArgumentDomain parses property-list values. Quote JSON as a string
        // or Foundation silently ignores the unquoted array-of-objects argument.
        let argument = String(decoding: try JSONEncoder().encode(json), as: UTF8.self)
        app.launchArguments = reviewLaunchArguments + ["-workoutLogEntriesData", argument]
        app.launch()
        app.tabBars.buttons["History"].tap()
        let first = app.buttons["workout-\(firstID)"]
        let second = app.buttons["workout-\(secondID)"]
        reveal(second, in: app)
        XCTAssertTrue(first.exists)
        let historyScreenshot = XCTAttachment(screenshot: app.screenshot())
        historyScreenshot.name = "Two workouts on the same day"
        historyScreenshot.lifetime = .keepAlways
        add(historyScreenshot)
        second.tap()
        XCTAssertTrue(app.staticTexts["Second workout"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["Delete"].tap()
        app.alerts["Delete workout?"].buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Second workout"].exists)
        app.navigationBars.buttons["Delete"].tap()
        app.alerts["Delete workout?"].buttons["Delete"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(second.exists)
        first.tap()
        XCTAssertTrue(app.staticTexts["First workout"].waitForExistence(timeout: 5))
    }
}
