import XCTest

final class WatchFlowTests: XCTestCase {
    private func screenshot(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testPrimaryActionAndResultWithoutScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let action = app.buttons["watch.companion"]
        XCTAssertTrue(action.waitForExistence(timeout: 12))
        let draw = app.buttons["daily.entry"], mood = app.buttons["watch.mood"]
        XCTAssertTrue(draw.isHittable && mood.isHittable)
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        XCTAssertGreaterThanOrEqual(action.frame.minY - app.frame.minY, 54)
        XCTAssertLessThan(action.frame.maxY, mood.frame.minY)
        XCTAssertLessThanOrEqual(mood.frame.maxY, app.frame.maxY - 8)
        screenshot(app, "watch-compact-home")
        action.tap()
        XCTAssertTrue(app.staticTexts["walk.unavailable"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        screenshot(app, "watch-walk-unavailable")
        app.buttons["walk.model"].tap()
        let result = app.staticTexts["companion.no-result"]
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        let retry = app.buttons["companion.start"]
        XCTAssertTrue(retry.isHittable)
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        screenshot(app, "watch-compact-retry")
        let demo = app.buttons["companion.demo"]
        XCTAssertTrue(demo.isHittable)
        demo.tap()
        XCTAssertTrue(app.staticTexts["示例"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "companion.response").firstMatch.exists)
        screenshot(app, "watch-compact-demo")
    }

    func testDrawEntryDoesNotTurnMissingRingsIntoReward() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let draw = app.buttons["daily.entry"]
        XCTAssertTrue(draw.waitForExistence(timeout: 12))
        draw.tap()
        XCTAssertTrue(app.buttons["daily.refresh"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["daily.reveal"].exists)
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        screenshot(app, "watch-compact-draw")
    }

    func testLargeTextCanReachMainAction() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--large-text-check"]; app.launch()
        let action = app.buttons["watch.companion"]
        XCTAssertTrue(action.waitForExistence(timeout: 12))
        XCTAssertTrue(action.isHittable)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
    }

    func testWalkSessionStartAndFinishOnOneScreen() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--walk-ui-test"]
        app.launch()
        let action = app.buttons["watch.companion"]
        XCTAssertTrue(action.waitForExistence(timeout: 12))
        action.tap()
        let steps = app.staticTexts["walk.steps"]
        XCTAssertTrue(steps.waitForExistence(timeout: 5))
        XCTAssertEqual(steps.label, "测试 12 步")
        let stop = app.buttons["walk.stop"]
        XCTAssertTrue(stop.isHittable)
        XCTAssertGreaterThanOrEqual(stop.frame.height, 44)
        XCTAssertLessThanOrEqual(stop.frame.maxY, app.frame.maxY - 8)
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        screenshot(app, "watch-walk-active-test")
        stop.tap()
        XCTAssertTrue(app.staticTexts["walk.finished"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        XCTAssertTrue(app.buttons["walk.model"].isHittable)
        screenshot(app, "watch-walk-finished-test")
    }
}
