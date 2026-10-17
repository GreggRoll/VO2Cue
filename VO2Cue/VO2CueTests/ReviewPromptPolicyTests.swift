import XCTest

final class ReviewPromptPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUp() {
        super.setUp()
        suiteName = "ReviewPromptPolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testOnboardingDoesNotDependOnRandomChance() {
        XCTAssertTrue(ReviewPromptPolicy(defaults: defaults).shouldRequest(afterOnboarding: true, now: now, randomValue: 0.99))
    }

    func testAlreadyReviewedSuppressesEveryRequest() {
        defaults.set(true, forKey: ReviewPromptPolicy.reviewedKey)
        let policy = ReviewPromptPolicy(defaults: defaults)
        XCTAssertFalse(policy.shouldRequest(afterOnboarding: true, now: now, randomValue: 0))
        XCTAssertFalse(policy.shouldRequest(afterOnboarding: false, now: now, randomValue: 0))
    }

    func testCooldownPersistsAcrossPolicyInstances() {
        ReviewPromptPolicy(defaults: defaults).recordRequest(now: now)
        let policy = ReviewPromptPolicy(defaults: defaults)
        XCTAssertFalse(policy.shouldRequest(afterOnboarding: true, now: now.addingTimeInterval(119 * 86_400), randomValue: 0))
        XCTAssertTrue(policy.shouldRequest(afterOnboarding: false, now: now.addingTimeInterval(120 * 86_400), randomValue: 0))
    }

    func testRandomRequestsAndRollingAnnualLimit() {
        let policy = ReviewPromptPolicy(defaults: defaults)
        XCTAssertFalse(policy.shouldRequest(afterOnboarding: false, now: now, randomValue: 0.25))
        XCTAssertTrue(policy.shouldRequest(afterOnboarding: false, now: now, randomValue: 0.24))
        for days in [0, 120, 240] {
            policy.recordRequest(now: now.addingTimeInterval(Double(days) * 86_400))
        }
        XCTAssertFalse(policy.shouldRequest(afterOnboarding: false, now: now.addingTimeInterval(360 * 86_400), randomValue: 0))
        XCTAssertTrue(policy.shouldRequest(afterOnboarding: false, now: now.addingTimeInterval(366 * 86_400), randomValue: 0))
    }
}
