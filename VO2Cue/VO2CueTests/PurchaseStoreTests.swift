import XCTest
import StoreKit
import StoreKitTest

@MainActor
final class PurchaseStoreTests: XCTestCase {
    private var session: SKTestSession!

    override func setUpWithError() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "VO2Cue", withExtension: "storekit"))
        session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.disableDialogs = true
        session.clearTransactions()
    }

    override func tearDownWithError() throws {
        session.clearTransactions()
        session = nil
    }

    func testAppStoreProductsUseTheRequestedPricesAndTypes() async throws {
        let store = PurchaseStore(checksPaidAppPurchase: false)
        await store.loadProducts()
        let monthly = try XCTUnwrap(store.product(id: PurchaseConfiguration.monthlyID))
        let lifetime = try XCTUnwrap(store.product(id: PurchaseConfiguration.lifetimeID))
        XCTAssertEqual(monthly.price, Decimal(string: "1.99"))
        XCTAssertEqual(monthly.type, .autoRenewable)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(monthly.subscription?.subscriptionPeriod.value, 1)
        XCTAssertEqual(lifetime.price, Decimal(string: "19.99"))
        XCTAssertEqual(lifetime.type, .nonConsumable)
    }

    func testLifetimePurchaseRestoresInANewStoreAndRefundRemovesAccess() async throws {
        let transaction = try await session.buyProduct(identifier: PurchaseConfiguration.lifetimeID)
        let store = PurchaseStore(checksPaidAppPurchase: false)
        await store.refreshAccess()
        XCTAssertEqual(store.access, .lifetime)
        XCTAssertTrue(store.watchAccess.allowsWorkout())
        XCTAssertNil(store.watchAccess.expiresAt)

        let reinstalledStore = PurchaseStore(checksPaidAppPurchase: false)
        await reinstalledStore.refreshAccess()
        XCTAssertEqual(reinstalledStore.access, .lifetime)

        try session.refundTransaction(identifier: UInt(transaction.id))
        try await waitUntilLocked(store)
        XCTAssertFalse(store.watchAccess.allowsWorkout())
    }

    func testMonthlyCancellationKeepsPaidAccessButExpiryLocksIt() async throws {
        let transaction = try await session.buyProduct(identifier: PurchaseConfiguration.monthlyID)
        let store = PurchaseStore(checksPaidAppPurchase: false)
        await store.loadProducts()
        await store.refreshAccess()
        XCTAssertEqual(store.access, .monthly)
        XCTAssertNotNil(store.watchAccess.expiresAt)

        try session.disableAutoRenewForTransaction(identifier: UInt(transaction.id))
        await store.refreshAccess()
        XCTAssertEqual(store.access, .monthly)

        try session.expireSubscription(productIdentifier: PurchaseConfiguration.monthlyID)
        try await waitUntilLocked(store)
    }

    func testCheckoutUnlocksLifetimeOnlyAfterStoreKitSuccess() async throws {
        let store = PurchaseStore(checksPaidAppPurchase: false)
        await store.start()
        XCTAssertEqual(store.access, .locked)
        let product = try XCTUnwrap(store.product(id: PurchaseConfiguration.lifetimeID))
        await store.purchase(product)
        XCTAssertEqual(store.access, .lifetime)
        XCTAssertFalse(store.canPurchase)
    }

    func testPendingApprovalDoesNotUnlockTheApp() async throws {
        session.askToBuyEnabled = true
        let store = PurchaseStore(checksPaidAppPurchase: false)
        await store.start()
        let product = try XCTUnwrap(store.product(id: PurchaseConfiguration.monthlyID))
        await store.purchase(product)
        XCTAssertFalse(store.isUnlocked)
        XCTAssertTrue(store.message?.contains("awaiting approval") == true)
    }

    private func waitUntilLocked(_ store: PurchaseStore) async throws {
        for _ in 0..<30 {
            await store.refreshAccess()
            if !store.isUnlocked { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("Revoked or expired purchase retained access")
    }
}
