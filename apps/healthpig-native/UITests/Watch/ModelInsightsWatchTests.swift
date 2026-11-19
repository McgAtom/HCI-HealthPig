import XCTest

final class ModelInsightsWatchTests: XCTestCase {
    func testTodayStatusKeepsAnalysisOnPhone() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["watch.companion"].waitForExistence(timeout: 12))
        XCTAssertTrue(app.buttons["watch.sleep"].isHittable)
        XCTAssertFalse(app.buttons["watch.status"].exists)
        XCTAssertFalse(app.buttons["watch.insights"].exists)
    }
}
