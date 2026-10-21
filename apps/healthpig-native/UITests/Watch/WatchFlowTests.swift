import XCTest

final class WatchFlowTests: XCTestCase {
    private let app = XCUIApplication()
    override func setUpWithError() throws { continueAfterFailure = false; app.launchArguments = [] }
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            let scroll = app.scrollViews.firstMatch
            guard scroll.waitForExistence(timeout: 5) else { return }
            if element.exists && element.isHittable && element.frame.midY > 75 && element.frame.midY < 220 { return }
            let down = element.exists && element.frame.midY <= 75
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.4 : 0.75))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: down ? 0.75 : 0.4))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
    }
    func testHomepagePrimaryActionStaysInsideWatchBezel() throws {
        app.launch()
        let action = app.buttons["watch.companion"]
        XCTAssertTrue(action.waitForExistence(timeout: 15))
        shot("24-watch-safe-home")
        let screen = app.frame, button = action.frame
        XCTAssertGreaterThanOrEqual(button.minX, screen.minX + 10, "Button needs space from the curved left edge")
        XCTAssertLessThanOrEqual(button.maxX, screen.maxX - 10, "Button needs space from the curved right edge")
        XCTAssertGreaterThanOrEqual(button.minY, screen.minY + 60, "Button must clear the navigation chrome")
        XCTAssertLessThanOrEqual(button.maxY, screen.maxY - 28, "Primary action must clear the curved bottom and page dots")
        XCTAssertGreaterThanOrEqual(button.height, 44, "Keep an easy touch target")
        XCTAssertEqual(action.label, "养猪")
        action.tap()
        let start = app.buttons["companion.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        shot("25-watch-safe-raising")
        XCTAssertGreaterThanOrEqual(start.frame.minX, screen.minX + 10)
        XCTAssertLessThanOrEqual(start.frame.maxX, screen.maxX - 10)
        XCTAssertLessThanOrEqual(start.frame.maxY, screen.maxY - 28, "Start must also stay above the curved bottom")
        XCTAssertGreaterThanOrEqual(start.frame.height, 44)
    }
    func testNativeDailyFlowAndSensorFailure() throws {
        app.launch()
        XCTAssertTrue(app.buttons["watch.review"].waitForExistence(timeout: 15))
        shot("01-watch-today")
        reveal(app.buttons["watch.capture"])
        app.buttons["watch.capture"].tap()
        let start = app.buttons["capture.start"]
        reveal(start); XCTAssertTrue(start.exists)
        shot("02-watch-capture-ready")
        start.tap()
        XCTAssertTrue(app.staticTexts["这次未能完成"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["重新采集"].exists)
        shot("03-watch-sensor-unavailable")

        app.terminate(); app.launch()
        let daily = app.buttons["daily.entry"]
        reveal(daily); XCTAssertTrue(daily.exists); daily.tap()
        let revealButton = app.buttons["daily.reveal"]
        if revealButton.exists {
            reveal(revealButton); shot("04-watch-daily-before-reveal"); revealButton.tap()
        }
        XCTAssertTrue(app.staticTexts["已存入收藏"].waitForExistence(timeout: 10))
        shot("05-watch-daily-revealed")
        let wear = app.buttons["daily.wear"]
        reveal(wear)
        if wear.isEnabled { wear.tap() }
        XCTAssertTrue(app.buttons["正在陪伴你"].exists)
        shot("06-watch-wearing")
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["watch.review"].waitForExistence(timeout: 10))
        shot("07-watch-persistent-companion")
    }
    func testCollectionAndTrendEmptyState() throws {
        app.launchArguments = ["--show-collection"]
        app.launch()
        XCTAssertTrue(app.buttons["collection.filter"].waitForExistence(timeout: 15))
        shot("08-watch-collection")
        app.buttons["collection.filter"].tap()
        XCTAssertTrue(app.switches["collection.only-owned"].waitForExistence(timeout: 10))
        app.switches["collection.only-owned"].tap()
        shot("09-watch-owned-filter")
        app.terminate(); app.launchArguments = ["--show-trends"]; app.launch()
        XCTAssertTrue(app.staticTexts["看看最近的节奏"].waitForExistence(timeout: 15))
        shot("10-watch-trends")
    }
    func testPublicExampleAnalysisAndDemoFeedback() throws {
        app.launch()
        XCTAssertTrue(app.buttons["watch.review"].waitForExistence(timeout: 15))
        reveal(app.buttons["watch.capture"])
        app.buttons["watch.capture"].tap()
        let entry = app.buttons["demo.entry"]; reveal(entry); entry.tap()
        let analyze = app.buttons["demo.analyze"]; reveal(analyze)
        XCTAssertTrue(analyze.waitForExistence(timeout: 10))
        shot("11-watch-demo-input")
        analyze.tap()
        let result = app.staticTexts["demo.result"]; reveal(result)
        XCTAssertTrue(result.exists)
        XCTAssertEqual(result.label, "更像步行")
        shot("12-watch-demo-analysis")
        let feedback = app.buttons["容易理解"]; reveal(feedback); feedback.tap()
        let saved = app.staticTexts["demo.feedback-saved"]; reveal(saved)
        XCTAssertTrue(saved.exists)
        shot("13-watch-demo-feedback")
    }

    func testSleepGuidanceAndNoSpoilerDraw() throws {
        app.launch(); XCTAssertTrue(app.buttons["watch.review"].waitForExistence(timeout: 15))
        reveal(app.buttons["watch.review"]); app.buttons["watch.review"].tap()
        let sleep = app.buttons["review.sleep"]; reveal(sleep); sleep.tap()
        let empty = app.staticTexts["sleep.empty-next-step"]; reveal(empty); XCTAssertTrue(empty.exists)
        shot("v7-watch-sleep-empty")
        app.terminate(); app.launchArguments = ["--show-collection"]; app.launch()
        let daily = app.buttons["collection.daily"]; reveal(daily); daily.tap()
        XCTAssertTrue(app.staticTexts["daily.status"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["daily.practice"].exists)
        shot("v7-watch-draw-no-demo")
    }

    func testLargeTextActionsAndHelp() throws {
        app.launchArguments = ["--large-text-check"]; app.launch(); let action = app.buttons["watch.companion"]
        XCTAssertTrue(action.waitForExistence(timeout: 15)); reveal(action)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        shot("v7-watch-home-large-type"); action.tap()
        let start = app.buttons["companion.start"]; reveal(start)
        XCTAssertTrue(start.exists); XCTAssertGreaterThanOrEqual(start.frame.height, 44)
        shot("v7-watch-raising-large-type")
        start.tap(); let failure = app.descendants(matching: .any).matching(identifier: "companion.no-result").firstMatch
        reveal(failure); XCTAssertTrue(failure.exists)
        shot("v7-watch-sensor-failure-large-type")
    }

    func testCompanionUnavailableAndPublicModelResponse() throws {
        app.launch()
        let companion = app.buttons["watch.companion"]
        XCTAssertTrue(companion.waitForExistence(timeout: 15)); shot("17-watch-raising-home"); companion.tap()
        let start = app.buttons["companion.start"]; reveal(start)
        shot("18-watch-companion-ready"); start.tap()
        let failure = app.descendants(matching: .any).matching(identifier: "companion.no-result").firstMatch
        reveal(failure); XCTAssertTrue(failure.waitForExistence(timeout: 15)); shot("19-watch-companion-no-sensor")
        let demo = app.buttons["companion.demo"]; reveal(demo); demo.tap()
        let analyze = app.buttons["demo.analyze"]; reveal(analyze); analyze.tap()
        let response = app.descendants(matching: .any).matching(identifier: "companion.response").firstMatch
        reveal(response); XCTAssertTrue(response.exists)
        XCTAssertTrue(response.label.contains("一起走")); shot("20-watch-companion-public-walking")
    }

    func testRingRuleDemoDoesNotReplaceRealData() throws {
        app.launch()
        let rings = app.buttons["watch.rings"]; reveal(rings); rings.tap()
        let unavailable = app.descendants(matching: .any).matching(identifier: "rings.unavailable").firstMatch
        XCTAssertTrue(unavailable.waitForExistence(timeout: 10)); shot("21-watch-rings-no-data")
        let demo = app.buttons["rings.demo"]; reveal(demo); demo.tap()
        let toggle = app.switches["rings.demo-complete"]; reveal(toggle); toggle.tap()
        let result = app.descendants(matching: .any).matching(identifier: "rings.demo-result").firstMatch
        reveal(result); XCTAssertTrue(result.label.contains("已达到")); shot("22-watch-rings-completed-demo")
    }

}
