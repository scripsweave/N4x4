//
//  N4x4UITestsLaunchTests.swift
//  N4x4UITests
//
//  Created by Jan van Rensburg on 9/12/24.
//

import XCTest

final class N4x4UITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        true
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    func testLaunch() throws {
        let app = XCUIApplication()
        // Keep these captures independent of previous workouts and permission flows.
        app.launchArguments = reviewLaunchArguments + ["-workoutLogEntriesData", "\"[]\""]
        app.launch()
        XCTAssertTrue(app.buttons["START"].waitForExistence(timeout: 15))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
