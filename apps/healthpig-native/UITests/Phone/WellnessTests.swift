import XCTest

extension XCUIApplication {
    func launchPastHealthSetup() {
        if !launchArguments.contains("-phoneHealthSetupHandledV1") {
            launchArguments += ["-phoneHealthSetupHandledV1", "YES"]
        }
        launch()
    }
}

final class WellnessTests: XCTestCase {
    private func shot(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func open(_ id: String, in app: XCUIApplication) {
        let item = app.buttons[id]
        XCTAssertTrue(item.waitForExistence(timeout: 10))
        item.tap()
    }

    private func back(_ title: String, in app: XCUIApplication) {
        let button = app.navigationBars[title].buttons.firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()
    }

    func testFirstRunOffersOneSetupAndSkippingPersists() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-phoneHealthSetupHandledV1", "NO"]
        app.launch()
        let request = app.buttons["health.setup-request"]
        XCTAssertTrue(request.waitForExistence(timeout: 10))
        shot(app, "phone-health-first-run")
        open("health.setup-skip", in: app)
        open("phone.wellness", in: app)
        open("wellness.vitals", in: app)
        XCTAssertTrue(app.buttons["vitals.resting"].waitForExistence(timeout: 5))
        XCTAssertFalse(request.exists)
        XCTAssertFalse(app.buttons["读取健康数据"].exists)

        app.terminate()
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["phone.wellness"].waitForExistence(timeout: 10))
        XCTAssertFalse(request.exists)
    }

    func testWellnessRoutesAndSleepPlan() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--wellness-ui-test"]
        app.launchEnvironment["HEALTHPIG_SLEEP_TEST_SUITE"] = "healthpig.sleep-ui.\(UUID())"
        app.launchPastHealthSetup()
        open("phone.wellness", in: app)
        shot(app, "wellness-hub")
        open("wellness.vitals", in: app)
        XCTAssertTrue(app.buttons["vitals.oxygen"].exists)
        shot(app, "wellness-vitals-empty")
        open("vitals.demo", in: app)
        XCTAssertTrue(app.staticTexts["示例数据"].waitForExistence(timeout: 5))
        shot(app, "wellness-vitals-demo")
        back("静息心率", in: app)
        back("身体指标", in: app)
        open("wellness.sleep", in: app)
        open("wellness.sleep-demo", in: app)
        XCTAssertTrue(app.staticTexts["示例数据"].waitForExistence(timeout: 5))
        shot(app, "wellness-sleep-stages-demo")
        back("睡眠阶段", in: app)
        open("wellness.sleep-plan", in: app)
        let proposal = app.staticTexts["sleep.proposal"]
        XCTAssertTrue(proposal.exists)
        XCTAssertTrue(app.staticTexts["sleep.wake-proposal"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sleep.latest").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sleep.routine").firstMatch.exists)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        shot(app, "phone-sleep-plan")
        let basis = app.buttons["sleep.basis"]
        XCTAssertTrue(basis.isHittable)
        basis.tap()
        XCTAssertTrue(app.navigationBars["推荐依据"].waitForExistence(timeout: 8))
        shot(app, "phone-sleep-basis")
        let inputs = app.buttons["sleep.forecast-insights"]
        XCTAssertTrue(inputs.waitForExistence(timeout: 8))
        if !inputs.isHittable { app.swipeUp() }
        inputs.tap()
        XCTAssertTrue(app.buttons["insights.feature.mean_minutes"].waitForExistence(timeout: 8))
        back("模型判断", in: app)
        XCTAssertTrue(app.navigationBars["推荐依据"].waitForExistence(timeout: 8))
        open("完成", in: app)
        let alarm = app.buttons["sleep.set-watch-alarm"]
        if alarm.exists {
            alarm.tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sleep.alarm-pending").firstMatch.exists
                          || app.descendants(matching: .any).matching(identifier: "sleep.alarm-confirmed").firstMatch.exists
                          || app.descendants(matching: .any).matching(identifier: "sleep.alarm-failed").firstMatch.exists)
            shot(app, "phone-wrist-alarm-request")
        } else {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sleep.watch-required").firstMatch.exists
                          || app.descendants(matching: .any).matching(identifier: "sleep.alarm-pending").firstMatch.exists
                          || app.descendants(matching: .any).matching(identifier: "sleep.alarm-confirmed").firstMatch.exists
                          || app.descendants(matching: .any).matching(identifier: "sleep.alarm-failed").firstMatch.exists)
        }
        back("睡眠计划", in: app)
        back("睡眠与作息", in: app)
        open("wellness.mood", in: app)
        XCTAssertFalse(app.buttons["divination.entry"].exists)
    }
}
