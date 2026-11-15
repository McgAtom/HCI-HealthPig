import XCTest

final class ModelInsightsWatchTests: XCTestCase {
    func testWatchCanOpenModelInsights() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let more = app.buttons.matching(identifier: "more.entry").firstMatch
        XCTAssertTrue(more.waitForExistence(timeout: 15))
        more.tap()
        let entry = app.buttons["watch.insights"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        if !entry.isHittable { app.swipeUp() }
        entry.tap()
        let feature = app.buttons["insights.feature.mag_abs_dev"]
        XCTAssertTrue(feature.waitForExistence(timeout: 10))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "04-watch-model-insights"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertTrue(feature.isHittable)
        feature.tap()
        XCTAssertTrue(app.staticTexts["验证集分布"].waitForExistence(timeout: 10))
        let scroll = app.scrollViews.firstMatch
        scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.77))
            .press(forDuration: 0.10, thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.34)))
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "04-watch-detail"; detail.lifetime = .keepAlways; add(detail)
    }
}
