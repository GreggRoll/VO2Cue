import XCTest

final class VO2CueUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-healthSavingEnabled", "NO", "-hasCompletedOnboarding", "YES", "-hasAlreadyReviewed", "YES", "-purchaseFixture", "paid"]
        app.launch()
    }

    func testOnboardingEndsAtHardPaywallAndStaysLockedAfterRelaunch() {
        app.terminate()
        app.launchArguments = ["-healthSavingEnabled", "NO", "-resetOnboarding", "-hasAlreadyReviewed", "YES", "-purchaseFixture", "locked"]
        app.launch()
        for title in ["More life.\nMore living.", "Feel fitter.\nLook the part.", "You move.\nWe cue.", "Your workout.\nYour way."] {
            XCTAssertTrue(app.staticTexts["onboardingTitle"].waitForExistence(timeout: 3))
            XCTAssertEqual(app.staticTexts["onboardingTitle"].label, title)
            captureScreen(title.replacingOccurrences(of: "\n", with: " "))
            app.buttons["onboardingContinue"].tap()
        }
        XCTAssertTrue(app.staticTexts["paywallTitle"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["plan_lifetime"].exists)
        XCTAssertTrue(app.buttons["plan_monthly"].exists)
        captureScreen("VO2Cue Paywall")
        XCTAssertFalse(app.tabBars.buttons["Workouts"].exists)
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["paywallTitle"].exists)
        app.terminate()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-hasAlreadyReviewed", "YES", "-purchaseFixture", "locked"]
        app.launch()
        XCTAssertTrue(app.staticTexts["paywallTitle"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.buttons["Workouts"].exists)
    }

    func testPaidBuyerBypassesPaywallAndKeepsLifetimeAccess() {
        XCTAssertTrue(app.tabBars.buttons["Workouts"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["paywallTitle"].exists)
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Early supporter")).firstMatch.waitForExistence(timeout: 3))
    }

    func testLifetimeBuyerCanUseTheAppWithoutARecurringSubscription() {
        app.terminate()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-hasAlreadyReviewed", "YES", "-purchaseFixture", "lifetime"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Workouts"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["paywallTitle"].exists)
    }

    private func captureScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testHeartSyncPreviewShowsPhaseTargetsAndClearsStaleOrPausedReadings() {
        for (fixture, target, status) in [("work", "Target 153–171", "In target"),
                                          ("recovery", "Target 108–126", "In target"),
                                          ("missing", "Target 153–171", "No fresh reading"),
                                          ("paused", "Target 153–171", "Workout paused")] {
            app.terminate()
            app.launchArguments = ["-hasCompletedOnboarding", "YES", "-hasAlreadyReviewed", "YES",
                                   "-purchaseFixture", "paid", "-heartSyncFixture", fixture, "-healthSavingEnabled", "NO"]
            app.launch()
            XCTAssertTrue(app.staticTexts["heartRateStatus"].waitForExistence(timeout: 5))
            XCTAssertEqual(app.staticTexts["heartRateStatus"].label, status)
            XCTAssertTrue(app.staticTexts[target].exists)
            if fixture == "work" || fixture == "recovery" {
                XCTAssertTrue(app.staticTexts["currentHeartRate"].label.contains(fixture == "work" ? "164" : "119"))
            } else {
                XCTAssertEqual(app.staticTexts["currentHeartRate"].label, "No current heart-rate reading")
            }
            XCTAssertTrue(app.staticTexts["Simulated preview · Debug only"].exists)
            captureScreen("Heart Sync \(fixture)")
        }
    }

    func testHeartSyncSettingsAndProfileGuidance() {
        app.tabBars.buttons["Settings"].tap()
        let targets = app.buttons["Heart-rate targets"]
        for _ in 0..<4 where !targets.isHittable { app.swipeUp() }
        targets.tap()
        let maximum = app.textFields["maximumHeartRate"]
        XCTAssertTrue(maximum.waitForExistence(timeout: 3))
        maximum.tap()
        maximum.clearAndType("180")
        app.buttons["Save maximum"].tap()
        XCTAssertTrue(app.staticTexts["Maximum saved"].waitForExistence(timeout: 3))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.tabBars.buttons["Workouts"].tap()
        app.buttons["New Workout"].tap()
        let toggle = app.switches["heartRateGuidanceToggle"]
        for _ in 0..<7 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.exists)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(toggle.value as? String, "1")
        let hardTarget = app.staticTexts["Hard, 153–171 BPM"]
        scrollTo(hardTarget)
        XCTAssertTrue(hardTarget.exists)
        let recoveryTarget = app.staticTexts["Recovery, 108–126 BPM"]
        scrollTo(recoveryTarget)
        XCTAssertTrue(recoveryTarget.exists)
        captureScreen("Heart Sync Profile Targets")
        app.navigationBars["Workout profile"].buttons["Cancel"].tap()
    }

    func testHeartSyncAtLargestAccessibilityTextSize() {
        app.terminate()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-hasAlreadyReviewed", "YES", "-purchaseFixture", "paid",
                               "-heartSyncFixture", "work", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let notNow = springboard.alerts["Apple Account Required"].buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) { notNow.tap() }
        XCTAssertTrue(app.staticTexts["currentHeartRate"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertEqual(app.staticTexts["heartRateStatus"].label, "In target")
        captureScreen("Heart Sync Largest Text")
        XCTAssertTrue(app.staticTexts["heartRateStatus"].isHittable)
        XCTAssertTrue(app.buttons["Pause"].isHittable)
    }

    func testFeedbackRequiresSubjectButMessageIsOptional() {
        app.tabBars.buttons["Settings"].tap()
        let feedback = app.buttons["Send feedback"]
        for _ in 0..<5 where !feedback.isHittable { app.swipeUp() }
        feedback.tap()
        let subject = app.textFields["feedbackSubject"]
        XCTAssertTrue(subject.waitForExistence(timeout: 3))
        let send = app.navigationBars["Send feedback"].buttons["Send"]
        XCTAssertFalse(send.isEnabled)
        subject.tap()
        subject.typeText("Just saying hi")
        XCTAssertTrue(send.isEnabled)
        XCTAssertFalse(app.staticTexts["adamsg_53@yahoo.com"].exists)
        app.navigationBars["Send feedback"].buttons["Cancel"].tap()
    }

    func testCreateCustomProfile() {
        app.buttons["New Workout"].tap()
        XCTAssertTrue(app.navigationBars["Workout profile"].waitForExistence(timeout: 3))

        let nameField = app.textFields["Name"]
        XCTAssertTrue(nameField.exists)
        nameField.tap()
        nameField.clearAndType("Pool 4×4")
        app.navigationBars["Workout profile"].buttons["Save"].tap()

        scrollTo(app.staticTexts["Pool 4×4"].firstMatch)
        XCTAssertTrue(app.staticTexts["Pool 4×4"].waitForExistence(timeout: 3))
    }

    func testWorkoutControlsAndHistory() {
        scrollTo(app.staticTexts["Norwegian 4×4"].firstMatch)
        app.staticTexts["Norwegian 4×4"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Norwegian 4×4"].waitForExistence(timeout: 3))

        let startButton = app.buttons["Start workout"]
        while !startButton.isHittable {
            app.swipeUp()
        }
        startButton.tap()

        let pauseButton = app.buttons["Pause"]
        XCTAssertTrue(pauseButton.waitForExistence(timeout: 3))
        pauseButton.tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 2))
        app.buttons["Resume"].tap()
        app.buttons["Skip"].tap()
        app.buttons["End"].tap()
        XCTAssertTrue(app.buttons["End workout"].waitForExistence(timeout: 2))
        app.buttons["End workout"].tap()

        XCTAssertTrue(app.staticTexts["Workout ended"].waitForExistence(timeout: 3))
        let duration = app.staticTexts["completedActualDuration"].label.split(separator: ":").compactMap { Int($0) }
        XCTAssertEqual(duration.count, 2)
        XCTAssertLessThan(duration[0] * 60 + duration[1], 600, "Skipping warmup must not add ten minutes")
        scrollTo(app.buttons["Done"])
        app.buttons["Done"].tap()
        app.tabBars.buttons["Progress"].tap()
        scrollTo(app.staticTexts["Norwegian 4×4"].firstMatch)
        XCTAssertTrue(app.staticTexts["Norwegian 4×4"].waitForExistence(timeout: 3))
    }

    func testWeeklyGoalCanBeEditedAndPersistsAfterRelaunch() {
        app.buttons["editWeeklyGoal"].tap()
        XCTAssertTrue(app.navigationBars["Weekly goal"].waitForExistence(timeout: 3))
        let stepper = app.steppers["weeklyGoalMinutes"]
        let original = stepper.label
        stepper.buttons["weeklyGoalMinutes-Increment"].tap()
        let expected = stepper.label
        XCTAssertNotEqual(original, expected)
        app.navigationBars["Weekly goal"].buttons["Save"].tap()
        let summary = app.staticTexts["weeklyGoalSummary"].label
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["weeklyGoalSummary"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["weeklyGoalSummary"].label, summary)
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["weeklyGoalSummary"].label, summary)
        captureScreen("Weekly progress")
    }

    func testWidgetStartOpensWorkoutAndPreservesRunningSession() throws {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workoutProfile_")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let id = String(row.identifier.dropFirst("workoutProfile_".count))
        let url = try XCTUnwrap(URL(string: "vo2cue://start-workout/\(id)"))
        XCUIDevice.shared.system.open(url)
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 10))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 3))
        XCUIDevice.shared.system.open(url)
        XCTAssertTrue(app.buttons["Resume"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["Pause"].exists, "A second widget tap must not replace or resume the paused workout")
        captureScreen("Widget start preserves paused workout")
        app.buttons["End"].tap()
        app.buttons["End workout"].tap()
        scrollTo(app.buttons["Done"])
        app.buttons["Done"].tap()
    }

    func testWidgetProgressColdLaunchAndStartCannotBypassPaywall() throws {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "workoutProfile_")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        let id = String(row.identifier.dropFirst("workoutProfile_".count))
        app.terminate()
        app.open(try XCTUnwrap(URL(string: "vo2cue://progress")))
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 5))
        app.terminate()
        app.launchArguments = ["-hasCompletedOnboarding", "YES", "-hasAlreadyReviewed", "YES", "-purchaseFixture", "locked"]
        app.open(try XCTUnwrap(URL(string: "vo2cue://start-workout/\(id)")))
        XCTAssertTrue(app.staticTexts["paywallTitle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Pause"].exists)
    }

    func testTemplatePreviewAddAndWorkoutReflectionPersists() {
        app.buttons["Browse workout library"].tap()
        app.descendants(matching: .any).matching(identifier: "workoutTemplate_easy20").firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Easy 20"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["20 minutes"].exists)
        captureScreen("Easy 20 template")
        scrollTo(app.buttons["addWorkoutTemplate"])
        app.buttons["addWorkoutTemplate"].tap()
        XCTAssertTrue(app.buttons["Browse workout library"].waitForExistence(timeout: 3))
        scrollTo(app.staticTexts["Easy 20"].firstMatch)
        app.staticTexts["Easy 20"].firstMatch.tap()
        scrollTo(app.buttons["Start workout"])
        app.buttons["Start workout"].tap()
        XCTAssertTrue(app.buttons["End"].waitForExistence(timeout: 10))
        app.buttons["Skip"].tap()
        app.buttons["End"].tap()
        app.buttons["End workout"].tap()
        XCTAssertTrue(app.staticTexts["Workout ended"].waitForExistence(timeout: 3))
        scrollTo(app.buttons["editWorkoutReflection"])
        app.buttons["editWorkoutReflection"].tap()
        captureScreen("Reflection editor state")
        XCTAssertTrue(app.navigationBars["Workout reflection"].waitForExistence(timeout: 3), app.debugDescription)
        let note = app.descendants(matching: .any).matching(identifier: "workoutNote").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3), app.debugDescription)
        note.tap()
        note.typeText("Easy treadmill session")
        app.navigationBars["Workout reflection"].buttons["Save"].tap()
        scrollTo(app.buttons["Done"])
        app.buttons["Done"].tap()
        app.tabBars.buttons["Progress"].tap()
        scrollTo(app.staticTexts["Easy 20"].firstMatch)
        app.staticTexts["Easy 20"].firstMatch.tap()
        scrollTo(app.staticTexts["Easy treadmill session"])
        XCTAssertTrue(app.staticTexts["Easy treadmill session"].exists)
        captureScreen("Workout summary and reflection")
        app.terminate()
        app.launch()
        app.tabBars.buttons["Progress"].tap()
        scrollTo(app.staticTexts["Easy 20"].firstMatch)
        app.staticTexts["Easy 20"].firstMatch.tap()
        scrollTo(app.staticTexts["Easy treadmill session"])
        XCTAssertTrue(app.staticTexts["Easy treadmill session"].exists)
    }

    func testReminderEditingStartsOffAndDisabledSaveDoesNotAskPermission() {
        app.tabBars.buttons["Settings"].tap()
        app.staticTexts["Workout reminders"].tap()
        XCTAssertTrue(app.navigationBars["Workout reminders"].waitForExistence(timeout: 3))
        let toggle = app.switches["workoutRemindersEnabled"]
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["reminderWeekday2"].waitForExistence(timeout: 3), app.debugDescription)
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["saveWorkoutReminders"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }

    func testAccessibilityTextCanReachLibraryAndProgress() {
        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["editWeeklyGoal"].waitForExistence(timeout: 3))
        captureScreen("Workouts with accessibility text")
        scrollTo(app.buttons["Browse workout library"])
        app.buttons["Browse workout library"].tap()
        let template = app.descendants(matching: .any).matching(identifier: "workoutTemplate_easy20").firstMatch
        scrollTo(template)
        template.tap()
        scrollTo(app.buttons["addWorkoutTemplate"])
        captureScreen("Template with accessibility text")
        app.buttons["addWorkoutTemplate"].tap()
        app.tabBars.buttons["Progress"].tap()
        XCTAssertTrue(app.navigationBars["Progress"].waitForExistence(timeout: 3))
        captureScreen("Progress with accessibility text")
    }

    private func scrollTo(_ element: XCUIElement) {
        for _ in 0..<12 {
            let navigationBar = app.navigationBars.firstMatch
            let top = navigationBar.exists && navigationBar.isHittable ? max(160, navigationBar.frame.maxY) : 160
            let tabBar = app.tabBars.firstMatch
            var bottom = tabBar.exists && tabBar.isHittable ? tabBar.frame.minY : app.frame.maxY - 30
            let done = app.buttons["Done"]
            if element.exists && element.label == "Done" && element.isHittable { return }
            if done.exists && done.isHittable && (!element.exists || element.label != "Done") {
                bottom = min(bottom, done.frame.minY)
            }
            if element.exists {
                let frame = element.frame
                if element.isHittable && frame.midY >= top && frame.midY < bottom { return }
                if frame.midY < top { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
}

private extension XCUIElement {
    func clearAndType(_ text: String) {
        guard let current = value as? String else {
            typeText(text)
            return
        }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        typeText(text)
    }
}
