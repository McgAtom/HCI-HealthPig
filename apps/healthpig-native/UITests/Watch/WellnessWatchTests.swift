import XCTest

final class WellnessWatchTests: XCTestCase {
    func testQuickMoodWithoutScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--wellness-ui-test"]
        app.launch()
        let mood = app.buttons["watch.mood"]
        XCTAssertTrue(mood.waitForExistence(timeout: 12)); mood.tap()
        let calm = app.buttons["watch.mood.calm"]
        XCTAssertTrue(calm.waitForExistence(timeout: 8))
        XCTAssertTrue(calm.isHittable && app.buttons["watch.mood.down"].isHittable)
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "watch-compact-mood"; shot.lifetime = .keepAlways; add(shot)
        calm.tap()
        XCTAssertTrue(app.staticTexts["陪你安静待一会"].exists)
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["watch.companion"].waitForExistence(timeout: 8))
    }
}
