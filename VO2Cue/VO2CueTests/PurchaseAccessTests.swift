import XCTest

final class PurchaseAccessTests: XCTestCase {
    private let cutoff = Date(timeIntervalSince1970: 1_800_000_000)

    func testOnlyProductionBuyersBeforeThePriceChangeKeepAccess() {
        XCTAssertTrue(PaidAppAccessPolicy.qualifies(originalPurchaseDate: cutoff.addingTimeInterval(-1), isProduction: true, cutoff: cutoff))
        XCTAssertFalse(PaidAppAccessPolicy.qualifies(originalPurchaseDate: cutoff, isProduction: true, cutoff: cutoff))
        XCTAssertFalse(PaidAppAccessPolicy.qualifies(originalPurchaseDate: cutoff.addingTimeInterval(1), isProduction: true, cutoff: cutoff))
        XCTAssertFalse(PaidAppAccessPolicy.qualifies(originalPurchaseDate: cutoff.addingTimeInterval(-1), isProduction: false, cutoff: cutoff))
    }

    func testPaidDownloadStageNeverChargesExistingBuyersAgain() {
        XCTAssertTrue(PaidAppAccessPolicy.qualifies(originalPurchaseDate: cutoff, isProduction: true, cutoff: nil))
        XCTAssertFalse(PaidAppAccessPolicy.qualifies(originalPurchaseDate: cutoff, isProduction: false, cutoff: nil))
    }

    func testWatchMonthlyAccessExpiresWhileLifetimePersists() {
        XCTAssertTrue(WatchPurchaseAccess(isUnlocked: true, expiresAt: nil).allowsWorkout(at: cutoff))
        XCTAssertFalse(WatchPurchaseAccess(isUnlocked: false, expiresAt: nil).allowsWorkout(at: cutoff))
        let monthly = WatchPurchaseAccess(isUnlocked: true, expiresAt: cutoff)
        XCTAssertTrue(monthly.allowsWorkout(at: cutoff.addingTimeInterval(-1)))
        XCTAssertFalse(monthly.allowsWorkout(at: cutoff))
    }

    func testProfilesAndPurchaseAccessCanShareApplicationContext() throws {
        let access = WatchPurchaseAccess(isUnlocked: true, expiresAt: cutoff)
        var payload = try WatchConnectivityPayload.encodeProfiles([.norwegian4x4])
        payload.merge(try WatchConnectivityPayload.encodeAccess(access)) { _, new in new }
        XCTAssertEqual(WatchConnectivityPayload.decodeProfiles(from: payload), [.norwegian4x4])
        XCTAssertEqual(WatchConnectivityPayload.decodeAccess(from: payload), access)
        XCTAssertNil(WatchConnectivityPayload.decodeAccess(from: [:]))
    }
}
