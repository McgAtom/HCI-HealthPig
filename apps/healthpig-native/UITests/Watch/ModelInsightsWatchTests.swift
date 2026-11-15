import XCTest

final class ModelInsightsWatchTests: XCTestCase {
    func testTodayStatusKeepsAnalysisOnPhone() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let status = app.buttons.matching(identifier: "watch.status").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 12))
        status.tap()
        XCTAssertTrue(app.staticTexts["详情在手机"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["watch.insights"].exists)
        XCTAssertFalse(app.scrollViews.firstMatch.exists)
    }
}
