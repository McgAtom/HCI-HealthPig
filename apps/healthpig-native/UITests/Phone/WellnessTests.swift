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

    func testWellnessRoutesAndLocalMood() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--wellness-ui-test"]
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
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "wellness.bedtime").firstMatch.exists)
        let proposal = app.staticTexts["sleep.proposal"]
        XCTAssertTrue(proposal.exists)
        XCTAssertTrue(app.staticTexts["按你的目标 · 睡眠记录不足"].exists)
        open("sleep.duration", in: app)
        open("8 小时 15 分", in: app)
        open("sleep.use-proposal", in: app)
        XCTAssertFalse(app.buttons["sleep.use-proposal"].exists)
        let save = app.buttons["wellness.save-sleep"]
        XCTAssertTrue(save.exists)
        if !save.isHittable { app.swipeUp() }
        if save.isEnabled { save.tap() }
        XCTAssertFalse(save.isEnabled)
        shot(app, "wellness-sleep-plan")
        back("作息计划", in: app)
        back("睡眠与作息", in: app)
        open("wellness.mood", in: app)
        open("wellness.mood.calm", in: app)
        XCTAssertTrue(app.staticTexts["陪你安静待一会"].exists)
        shot(app, "wellness-mood")
        app.terminate()
        app.launchPastHealthSetup()
        open("phone.wellness", in: app)
        open("wellness.mood", in: app)
        XCTAssertTrue(app.staticTexts["陪你安静待一会"].exists)
        open("wellness.delete-mood", in: app)
        let delete = app.alerts.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let response = app.staticTexts["陪你安静待一会"]
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: response)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
    }
}
