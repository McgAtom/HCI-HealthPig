import XCTest

final class ModelInsightsTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let result = XCTAttachment(screenshot: app.screenshot())
        result.name = name
        result.lifetime = .keepAlways
        add(result)
    }

    func testRankingDistributionAndExamples() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        let entry = app.buttons["phone.model-insights"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15))
        shot(app, "04-phone-today")
        entry.tap()
        let largest = app.buttons["insights.feature.mag_abs_dev"]
        XCTAssertTrue(largest.waitForExistence(timeout: 10))
        XCTAssertTrue((largest.value as? String ?? "").contains("+42.69"))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "insights.not-causal").firstMatch.exists)
        let negative = app.buttons["insights.feature.spectral_entropy"]
        XCTAssertTrue((negative.value as? String ?? "").contains("-0.08"))
        shot(app, "04-phone-ranking")
        largest.tap()
        XCTAssertTrue(app.staticTexts["验证集分布"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["12,993 窗口"].exists)
        XCTAssertTrue(app.staticTexts["30 人"].exists)
        let expandable = app.descendants(matching: .any).matching(identifier: "insights.case-inputs").firstMatch
        if expandable.exists {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "insights.case.correct").firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "insights.case.wrong").firstMatch.exists)
            shot(app, "04-phone-distribution-and-cases")
            if !expandable.isHittable { app.swipeUp() }
            expandable.tap()
            XCTAssertTrue(app.staticTexts["平均幅值"].exists)
        } else {
            // The public source distribution deliberately omits private row examples.
            shot(app, "04-phone-public-distribution")
        }
        app.buttons["完成"].tap()
        let all = app.buttons["insights.all-features"]
        if !all.isHittable { app.swipeUp() }
        all.tap()
        XCTAssertTrue(app.buttons["insights.feature.mag_mean"].exists)
        shot(app, "04-phone-all-features")
    }

    func testLargeTextCanReachFeature() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--large-text-check"]
        app.launch()
        let tab = app.tabBars.buttons["判断"]
        XCTAssertTrue(tab.waitForExistence(timeout: 15))
        tab.tap()
        let largest = app.buttons["insights.feature.mag_abs_dev"]
        XCTAssertTrue(largest.waitForExistence(timeout: 10))
        if !largest.isHittable { app.swipeUp() }
        shot(app, "04-phone-large-text")
        largest.tap()
        XCTAssertTrue(app.staticTexts["验证集分布"].waitForExistence(timeout: 10))
    }
}
