import XCTest
import UIKit

final class PhoneFlowTests: XCTestCase {
    func testNativeTabsAndCollection() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["猪猪"].waitForExistence(timeout: 20))
        func shot(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        shot("01-phone-today")
        app.tabBars.buttons["猪猪"].tap()
        XCTAssertTrue(app.switches["collection.only-owned"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["locked.pig-001"].exists)
        XCTAssertFalse(app.buttons["card.pig-001"].exists)
        shot("02-phone-collection")
        app.switches["collection.only-owned"].tap()
        shot("03-phone-owned-filter")
        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.staticTexts["看看最近的节奏"].waitForExistence(timeout: 10))
        shot("04-phone-trends-empty")
        app.tabBars.buttons["更多"].tap()
        app.buttons["audit.entry"].tap()
        XCTAssertTrue(app.staticTexts["独立研究审核"].waitForExistence(timeout: 10))
        shot("05-phone-audit-catalog")
        app.buttons["audit.walk"].tap()
        XCTAssertTrue(app.staticTexts["整体表现"].waitForExistence(timeout: 10))
        shot("06-phone-audit-detail")
    }
    func testPublicExampleCanChangeInputAndExplain() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["更多"].waitForExistence(timeout: 20))
        app.tabBars.buttons["更多"].tap()
        app.buttons["demo.entry"].tap()
        let analyze = app.buttons["demo.analyze"]
        XCTAssertTrue(analyze.waitForExistence(timeout: 10)); analyze.tap()
        XCTAssertTrue(app.staticTexts["demo.result"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["demo.result"].label, "更像步行")
        func shot(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        shot("07-phone-demo-walking")
        app.segmentedControls.buttons["坐／站示例"].tap()
        XCTAssertFalse(app.staticTexts["demo.result"].exists)
        analyze.tap()
        XCTAssertEqual(app.staticTexts["demo.result"].label, "更像坐／站")
        shot("08-phone-demo-input-changed")
        let feedback = app.buttons["容易理解"]
        for _ in 0..<4 { if feedback.isHittable { break }; app.scrollViews.firstMatch.swipeUp() }
        feedback.tap()
        XCTAssertTrue(app.staticTexts["demo.feedback-saved"].exists)
        shot("09-phone-demo-feedback")
    }

    func testPairedSyncAcknowledgement() throws {
        // Run with the paired Watch app in the foreground.
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["更多"].waitForExistence(timeout: 20))
        app.tabBars.buttons["更多"].tap()
        let retry = app.buttons["sync.retry"]
        for _ in 0..<4 { if retry.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(retry.exists); retry.tap()
        let status = app.descendants(matching: .any).matching(identifier: "sync.status").firstMatch
        let acknowledged = NSPredicate { _, _ in
            status.exists && ["对端已保存本次同步", "已接收并保存在本机"].contains(status.label)
        }
        expectation(for: acknowledged, evaluatedWith: nil)
        waitForExpectations(timeout: 20)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "10-phone-paired-sync"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testPhoneDailyClaimAndWear() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let entry = app.buttons["phone.daily-entry"]
        XCTAssertTrue(entry.waitForExistence(timeout: 20))
        for _ in 0..<4 { if entry.isHittable { break }; app.swipeUp() }
        entry.tap()
        let reveal = app.buttons["daily.reveal"]
        if reveal.exists {
            for _ in 0..<4 { if reveal.isHittable { break }; app.swipeUp() }
            reveal.tap()
        }
        XCTAssertTrue(app.staticTexts["已存入收藏"].waitForExistence(timeout: 10))
        let wear = app.buttons["daily.wear"]
        for _ in 0..<4 { if wear.isHittable { break }; app.swipeUp() }
        if wear.isEnabled { wear.tap() }
        XCTAssertFalse(wear.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "11-phone-daily-wearing"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testSleepGuidanceAndNoSpoilerDraw() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        let review = app.buttons["phone.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 20))
        for _ in 0..<5 { if review.isHittable { break }; app.swipeUp() }; review.tap()
        let sleep = app.buttons["review.sleep"]
        for _ in 0..<5 { if sleep.isHittable { break }; app.swipeUp() }; sleep.tap()
        XCTAssertTrue(app.staticTexts["sleep.empty-next-step"].waitForExistence(timeout: 10))
        var image = XCTAttachment(screenshot: app.screenshot()); image.name = "v7-phone-sleep-empty"; image.lifetime = .keepAlways; add(image)
        app.terminate(); app.launch(); app.tabBars.buttons["猪猪"].tap(); app.buttons["collection.daily"].tap()
        XCTAssertTrue(app.staticTexts["daily.status"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["daily.practice"].exists)
        XCTAssertFalse(app.buttons["daily.practice-reveal"].exists)
        image = XCTAttachment(screenshot: app.screenshot()); image.name = "v7-phone-draw-no-demo"; image.lifetime = .keepAlways; add(image)
    }

    func testEditableInputErrorRecoveryAndHelp() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["更多"].waitForExistence(timeout: 20)); app.tabBars.buttons["更多"].tap()
        app.buttons["demo.entry"].tap()
        app.buttons["demo.analyze"].tap()
        XCTAssertTrue(app.staticTexts["demo.result"].waitForExistence(timeout: 10))
        app.buttons["demo.edit"].tap()
        let clear = app.buttons["input.clear"]
        for _ in 0..<6 { if clear.isHittable { break }; app.swipeUp() }; clear.tap()
        app.buttons["input.apply"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "input.error").firstMatch.waitForExistence(timeout: 5))
        var image = XCTAttachment(screenshot: app.screenshot()); image.name = "v7-phone-input-error"; image.lifetime = .keepAlways; add(image)
        let restore = app.buttons["input.restore"]
        for _ in 0..<5 { if restore.isHittable { break }; app.swipeUp() }; restore.tap()
        app.buttons["input.apply"].tap()
        XCTAssertTrue(app.buttons["demo.analyze"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.result"].exists)
        app.buttons["demo.analyze"].tap()
        XCTAssertTrue(app.staticTexts["demo.result"].waitForExistence(timeout: 5))
        image = XCTAttachment(screenshot: app.screenshot()); image.name = "v7-phone-input-recovered"; image.lifetime = .keepAlways; add(image)
        app.terminate(); app.launch(); app.tabBars.buttons["更多"].tap()
        let help = app.buttons["accessibility.help"]
        for _ in 0..<8 { if help.isHittable { break }; app.swipeUp() }; help.tap()
        XCTAssertTrue(app.staticTexts["放大文字"].waitForExistence(timeout: 5))
        image = XCTAttachment(screenshot: app.screenshot()); image.name = "v7-phone-accessibility-help"; image.lifetime = .keepAlways; add(image)
    }

    func testLargeTextHomeAndCollection() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--large-text-check"]; app.launch()
        XCTAssertTrue(app.buttons["phone.daily-entry"].waitForExistence(timeout: 20))
        var image = XCTAttachment(screenshot: app.screenshot()); image.name = "v7-phone-home-large-type"; image.lifetime = .keepAlways; add(image)
        app.tabBars.buttons["猪猪"].tap()
        XCTAssertTrue(app.buttons["collection.daily"].waitForExistence(timeout: 10))
        image = XCTAttachment(screenshot: app.screenshot()); image.name = "v7-phone-collection-large-type"; image.lifetime = .keepAlways; add(image)
    }

    func testRingRulesAndCompanionModelResponsesAreIsolatedDemos() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["phone.rings"].waitForExistence(timeout: 20)); app.buttons["phone.rings"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "rings.unavailable").firstMatch.waitForExistence(timeout: 10))
        var attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "15-phone-rings-no-data"; attachment.lifetime = .keepAlways; add(attachment)
        let demo = app.buttons["rings.demo"]
        for _ in 0..<5 { if demo.isHittable { break }; app.swipeUp() }; demo.tap()
        app.switches["rings.demo-complete"].tap()
        let complete = app.descendants(matching: .any).matching(identifier: "rings.demo-result").firstMatch
        XCTAssertTrue(complete.label.contains("已达到"))
        attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "16-phone-rings-completed-demo"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launch(); app.tabBars.buttons["更多"].tap()
        let companion = app.buttons["companion.demo"]
        for _ in 0..<4 { if companion.isHittable { break }; app.swipeUp() }; companion.tap()
        app.buttons["demo.analyze"].tap()
        let response = app.descendants(matching: .any).matching(identifier: "companion.response").firstMatch
        XCTAssertTrue(response.label.contains("一起走"))
        attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "17-phone-companion-public-walking"; attachment.lifetime = .keepAlways; add(attachment)
        app.segmentedControls.buttons["坐／站示例"].tap()
        XCTAssertFalse(response.exists); app.buttons["demo.analyze"].tap()
        XCTAssertTrue(response.label.contains("停下来休息"))
        attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "18-phone-companion-public-still"; attachment.lifetime = .keepAlways; add(attachment)
    }

    func testHomeAccessibilityContrastAndDescriptions() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["phone.daily-entry"].waitForExistence(timeout: 20))
        if #available(iOS 17.0, *) {
            try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription])
        }
    }

    private func evidence(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name + "-accessibility-tree"; tree.lifetime = .keepAlways; add(tree)
    }

    private func openInput(_ app: XCUIApplication, captureMore: Bool = false) {
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["更多"].waitForExistence(timeout: 20))
        app.tabBars.buttons["更多"].tap()
        if captureMore {
            XCTAssertTrue(app.buttons["demo.entry"].isHittable)
            XCTAssertTrue(app.buttons["accessibility.help"].isHittable)
            evidence(app, "a11y-phone-more")
        }
        app.buttons["demo.entry"].tap(); app.buttons["demo.edit"].tap()
        XCTAssertTrue(app.buttons["input.apply"].waitForExistence(timeout: 10))
    }

    func testAccessibilityInputAudit() throws {
        let app = XCUIApplication(); openInput(app, captureMore: true)
        evidence(app, "a11y-input")
        try app.performAccessibilityAudit(for: [.sufficientElementDescription, .hitRegion, .textClipped])
    }

    func testInputContrastAudit() throws {
        let app = XCUIApplication(); openInput(app)
        // Run contrast independently of the text-resizing audit. Earlier combined checks
        // produced warnings; retain those results and verify actual screenshot color pairs too.
        try app.performAccessibilityAudit(for: [.contrast])
        evidence(app, "a11y-input-contrast-review")
    }

    func testKeyboardEditingRecoveryAndReanalysis() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); openInput(app)
        let field = app.descendants(matching: .any).matching(identifier: "input.single-value").firstMatch
        XCTAssertTrue(field.exists); field.tap(); field.typeText("--")
        evidence(app, "a11y-keyboard-typed")
        field.typeText("\n")
        let error = app.descendants(matching: .any).matching(identifier: "input.error").firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        evidence(app, "a11y-keyboard-input-error")
        XCTAssertTrue((field.value as? String ?? "").contains("--"), "Keep the invalid value for correction")
        let restore = app.buttons["input.restore"]
        for _ in 0..<5 { if restore.isHittable { break }; app.swipeUp() }
        restore.tap()
        app.buttons["input.apply"].tap()
        XCTAssertTrue(app.buttons["demo.analyze"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["demo.result"].exists)
        app.buttons["demo.analyze"].tap()
        XCTAssertTrue(app.staticTexts["demo.result"].waitForExistence(timeout: 5))
        evidence(app, "a11y-keyboard-reanalysis")
        try app.performAccessibilityAudit(for: [.hitRegion, .sufficientElementDescription, .textClipped])
        app.buttons["demo.edit"].tap()
        let again = app.descendants(matching: .any).matching(identifier: "input.single-value").firstMatch
        again.tap(); app.buttons["input.dismiss-keyboard"].tap(); app.buttons["input.cancel"].tap()
        XCTAssertTrue(app.buttons["demo.analyze"].waitForExistence(timeout: 5))
        evidence(app, "a11y-keyboard-cancel")
    }

    func testAccessibilityHealthEmptyAndResultAudit() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.buttons["phone.review"].waitForExistence(timeout: 20))
        app.buttons["phone.review"].tap()
        evidence(app, "a11y-health-empty")
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription, .hitRegion, .textClipped])
        app.terminate(); app.launch(); app.tabBars.buttons["更多"].tap(); app.buttons["demo.entry"].tap()
        app.buttons["demo.analyze"].tap()
        XCTAssertTrue(app.staticTexts["demo.result"].waitForExistence(timeout: 5))
        evidence(app, "a11y-model-result")
        try app.performAccessibilityAudit(for: [.contrast, .sufficientElementDescription, .hitRegion, .textClipped])
    }

    func testSystemLargeTextInputAndRecovery() throws {
        // Set the simulator's real content_size before running; no Debug size injection.
        try XCTSkipUnless(UIApplication.shared.preferredContentSizeCategory.isAccessibilityCategory, "Requires a system accessibility text size")
        continueAfterFailure = false
        let app = XCUIApplication(); openInput(app)
        let field = app.descendants(matching: .any).matching(identifier: "input.single-value").firstMatch
        XCTAssertTrue(field.exists)
        evidence(app, "a11y-system-large-input-top")
        for _ in 0..<7 { if field.isHittable && field.frame.maxY < app.frame.maxY - 30 { break }; app.swipeUp() }
        evidence(app, "a11y-system-large-input")
        try app.performAccessibilityAudit(for: [.textClipped, .sufficientElementDescription])
        let apply = app.buttons["input.apply"]
        for _ in 0..<7 { if apply.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(apply.isHittable); XCTAssertGreaterThanOrEqual(apply.frame.height, 44)
        apply.tap()
        XCTAssertTrue(app.buttons["demo.analyze"].waitForExistence(timeout: 5))
        for _ in 0..<7 { if app.buttons["demo.analyze"].isHittable { break }; app.swipeUp() }
        app.buttons["demo.analyze"].tap()
        let result = app.staticTexts["demo.result"]
        for _ in 0..<7 { if result.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(result.exists); evidence(app, "a11y-system-large-result")
    }

    func testSystemReducedMotionCompanionResponse() throws {
        // Enable Reduce Motion in Device Hub's actual simulator settings before running.
        try XCTSkipUnless(UIAccessibility.isReduceMotionEnabled, "Requires the system Reduce Motion setting")
        continueAfterFailure = false
        let app = XCUIApplication(); app.launch()
        XCTAssertTrue(app.tabBars.buttons["更多"].waitForExistence(timeout: 20)); app.tabBars.buttons["更多"].tap()
        let entry = app.buttons["companion.demo"]
        for _ in 0..<6 { if entry.isHittable { break }; app.swipeUp() }; entry.tap()
        app.buttons["demo.analyze"].tap()
        let response = app.descendants(matching: .any).matching(identifier: "companion.response").firstMatch
        for _ in 0..<6 { if response.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(response.exists); XCTAssertTrue(response.label.contains("一起走"))
        XCTAssertTrue((response.value as? String ?? "").contains("静态回应"))
        evidence(app, "a11y-system-reduced-motion-response")
        app.segmentedControls.buttons["坐／站示例"].tap()
        XCTAssertFalse(response.exists); app.buttons["demo.analyze"].tap()
        for _ in 0..<6 { if response.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(response.label.contains("停下来休息"))
        XCTAssertTrue((response.value as? String ?? "").contains("静态回应"))
        evidence(app, "a11y-system-reduced-motion-still")
    }

}
