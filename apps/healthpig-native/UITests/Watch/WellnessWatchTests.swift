import XCTest

final class WellnessWatchTests: XCTestCase {
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testQuickMoodRevealsOneDailyCard() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HEALTHPIG_DIVINATION_TEST_SUITE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["watch.companion"].waitForExistence(timeout: 12))
        app.swipeUp()
        let tired = app.buttons["watch.mood.tired"]
        XCTAssertTrue(tired.waitForExistence(timeout: 8))
        XCTAssertTrue(tired.isHittable && app.buttons["watch.mood.down"].isHittable && app.buttons["watch.mood.bright"].isHittable)
        let custom = app.descendants(matching: .any).matching(identifier: "watch.mood.custom").firstMatch
        XCTAssertTrue(custom.isHittable)
        screenshot(app, "watch-mood")
        tired.tap()
        let card = app.staticTexts["divination.card-title"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        XCTAssertTrue(["喘息", "边界", "松开"].contains(card.label))
        XCTAssertEqual(app.staticTexts["watch.mood-recorded"].label, "累")
        XCTAssertFalse(tired.exists)
        screenshot(app, "watch-mood-card")
        let title = card.label
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["watch.companion"].waitForExistence(timeout: 12))
        app.swipeUp()
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertEqual(card.label, title)
    }

    func testCustomMoodUsesSystemTextEntry() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["HEALTHPIG_DIVINATION_TEST_SUITE"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["watch.companion"].waitForExistence(timeout: 12))
        app.swipeUp()
        let custom = app.descendants(matching: .any).matching(identifier: "watch.mood.custom").firstMatch
        XCTAssertTrue(custom.waitForExistence(timeout: 8))
        custom.tap()
        let done = app.buttons.matching(NSPredicate(format: "label == 'Done' OR label == '完成'")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 8), app.debugDescription)
        screenshot(app, "watch-custom-mood")
        app.typeText("今天好累")
        done.tap()
        let card = app.staticTexts["divination.card-title"]
        XCTAssertTrue(card.waitForExistence(timeout: 8))
        XCTAssertTrue(["喘息", "边界", "松开"].contains(card.label))
        XCTAssertEqual(app.staticTexts["watch.mood-recorded"].label, "今天好累")
        screenshot(app, "watch-custom-mood-card")
    }

    func testWristSleepShowsTimesAndSchedulesOrReportsFailure() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--wellness-ui-test"]
        app.launch()
        let sleep = app.buttons["watch.sleep"]
        XCTAssertTrue(sleep.waitForExistence(timeout: 12)); sleep.tap()
        XCTAssertTrue(app.staticTexts["sleep.proposal"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["sleep.wake-proposal"].isHittable)
        let action = app.buttons["sleep.set-alarm"]
        let scheduled = app.buttons["sleep.alarm-confirmed"]
        XCTAssertTrue(action.isHittable || scheduled.isHittable)
        screenshot(app, "watch-sleep-plan")
        if scheduled.exists { scheduled.tap() }
        XCTAssertTrue(action.waitForExistence(timeout: 8)); action.tap()
        let failed = app.descendants(matching: .any).matching(identifier: "sleep.alarm-failed").firstMatch
        let outcome = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in scheduled.exists || failed.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [outcome], timeout: 12), .completed)
        if scheduled.exists {
            screenshot(app, "watch-alarm-confirmed")
            scheduled.tap()
            XCTAssertTrue(action.waitForExistence(timeout: 8))
        } else {
            XCTAssertTrue(action.isHittable)
            screenshot(app, "watch-alarm-failed")
        }
    }
}
