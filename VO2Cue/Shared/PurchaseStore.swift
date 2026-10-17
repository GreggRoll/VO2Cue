import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseStore {
    enum Access: Equatable {
        case checking, locked, unavailable, monthly, lifetime, paidApp

        var isUnlocked: Bool { self == .monthly || self == .lifetime || self == .paidApp }

        var title: String {
            switch self {
            case .checking: "Checking purchases…"
            case .locked: "Choose a plan"
            case .unavailable: "Couldn’t verify purchases"
            case .monthly: "Monthly membership"
            case .lifetime: "Lifetime access"
            case .paidApp: "Lifetime access · Early supporter"
            }
        }
    }

    private(set) var access: Access = .checking
    private(set) var products: [Product] = []
    private(set) var isLoadingProducts = false
    private(set) var isPurchasing = false
    private(set) var isRestoring = false
    private(set) var message: String?
    private(set) var subscriptionExpiresAt: Date?
    private(set) var hasCheckedPurchases = false

    var isUnlocked: Bool { access.isUnlocked }
    var isBusy: Bool { isPurchasing || isRestoring }
    var canPurchase: Bool { hasCheckedPurchases && access == .locked && !isBusy }
    var watchAccess: WatchPurchaseAccess {
        WatchPurchaseAccess(isUnlocked: isUnlocked, expiresAt: access == .monthly ? subscriptionExpiresAt : nil)
    }

    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var statusTask: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var started = false
    @ObservationIgnored private let checksPaidAppPurchase: Bool

    init(checksPaidAppPurchase: Bool = true) {
        self.checksPaidAppPurchase = checksPaidAppPurchase
        #if DEBUG
        // UI fixtures are compile-time excluded from Release/TestFlight builds.
        if let fixture = Self.uiFixture {
            access = fixture == "paid" ? .paidApp : fixture == "lifetime" ? .lifetime : .locked
            hasCheckedPurchases = true
        }
        #endif
    }

    deinit {
        updatesTask?.cancel()
        statusTask?.cancel()
    }

    func product(id: String) -> Product? { products.first { $0.id == id } }

    func start() async {
        #if DEBUG
        if Self.uiFixture != nil { return }
        #endif
        if !started {
            started = true
            updatesTask = Task { [weak self] in
                for await result in Transaction.updates {
                    guard !Task.isCancelled else { return }
                    guard case .verified(let transaction) = result,
                          PurchaseConfiguration.productIDs.contains(transaction.productID) else { continue }
                    await self?.refreshAccess()
                    await transaction.finish()
                }
            }
            statusTask = Task { [weak self] in
                for await status in Product.SubscriptionInfo.Status.updates {
                    guard !Task.isCancelled else { return }
                    guard case .verified(let transaction) = status.transaction,
                          transaction.productID == PurchaseConfiguration.monthlyID else { continue }
                    await self?.refreshAccess()
                }
            }
        }
        await refreshAccess()
        if access == .paidApp || access == .lifetime { return }
        await loadProducts()
        if access == .monthly { await refreshAccess() }
    }

    func loadProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        do {
            products = try await Product.products(for: PurchaseConfiguration.productIDs).filter {
                ($0.id == PurchaseConfiguration.monthlyID && $0.type == .autoRenewable &&
                 $0.subscription?.subscriptionPeriod.unit == .month &&
                 $0.subscription?.subscriptionPeriod.value == 1) ||
                ($0.id == PurchaseConfiguration.lifetimeID && $0.type == .nonConsumable)
            }
            if products.count != PurchaseConfiguration.productIDs.count {
                message = "Some plans are unavailable from the App Store. Please try again."
            }
        } catch {
            message = "Couldn’t load App Store prices. Check your connection and try again."
        }
    }

    func refreshAccess() async {
        #if DEBUG
        if Self.uiFixture != nil { return }
        #endif
        // An update arriving during a scan must trigger another scan, not get lost.
        guard !isRefreshing else { needsRefresh = true; return }
        isRefreshing = true
        repeat {
            needsRefresh = false
            await scanAccess()
        } while needsRefresh
        isRefreshing = false
    }

    private func scanAccess() async {
        var hasLifetime = false
        var hasMonthly = false
        var expiresAt: Date?
        var verificationFailed = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                verificationFailed = true
                continue
            }
            guard transaction.revocationDate == nil, !transaction.isUpgraded else { continue }
            if transaction.productID == PurchaseConfiguration.lifetimeID && transaction.productType == .nonConsumable {
                hasLifetime = true
            } else if transaction.productID == PurchaseConfiguration.monthlyID && transaction.productType == .autoRenewable {
                // currentEntitlements includes subscribed and billing-grace-period
                // access. Don't reject grace-period users by comparing expiry here.
                hasMonthly = true
                expiresAt = transaction.expirationDate
            }
        }
        if hasMonthly, let subscription = product(id: PurchaseConfiguration.monthlyID)?.subscription,
           let statuses = try? await subscription.status {
            for status in statuses where status.state == .inGracePeriod {
                if case .verified(let transaction) = status.transaction,
                   transaction.productID == PurchaseConfiguration.monthlyID,
                   case .verified(let renewal) = status.renewalInfo,
                   let graceExpiry = renewal.gracePeriodExpirationDate {
                    expiresAt = max(expiresAt ?? graceExpiry, graceExpiry)
                }
            }
        }

        #if os(iOS)
        var isPaidBuyer = false
        if checksPaidAppPurchase {
            do {
                switch try await AppTransaction.shared {
                case .verified(let appTransaction):
                    isPaidBuyer = PaidAppAccessPolicy.qualifies(
                        originalPurchaseDate: appTransaction.originalPurchaseDate,
                        isProduction: appTransaction.environment == .production,
                        cutoff: PurchaseConfiguration.paidDownloadCutoff
                    )
                case .unverified:
                    verificationFailed = true
                }
            } catch {
                verificationFailed = true
            }
        }
        #endif

        subscriptionExpiresAt = expiresAt
        #if os(iOS)
        access = isPaidBuyer ? .paidApp : hasLifetime ? .lifetime : hasMonthly ? .monthly : verificationFailed ? .unavailable : .locked
        #else
        access = hasLifetime ? .lifetime : hasMonthly ? .monthly : verificationFailed ? .unavailable : .locked
        #endif
        hasCheckedPurchases = true
        if access == .unavailable {
            message = "Couldn’t verify your purchases. Please retry or restore purchases before choosing a plan."
        }
    }

    func purchase(_ product: Product) async {
        guard canPurchase, PurchaseConfiguration.productIDs.contains(product.id) else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            switch try await product.purchase() {
            case .success(let result):
                guard case .verified(let transaction) = result else {
                    message = "Apple couldn’t verify this purchase. Please restore purchases and try again."
                    return
                }
                await refreshAccess()
                await transaction.finish()
                if !isUnlocked { message = "Your purchase is processing. Please restore purchases in a moment." }
            case .pending:
                message = "Your purchase is awaiting approval. Access will unlock once Apple confirms it."
            case .userCancelled:
                break
            @unknown default:
                message = "Purchase not completed. Please try again."
            }
        } catch {
            message = "Purchase not completed. \(error.localizedDescription)"
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isRestoring = true
        message = nil
        defer { isRestoring = false }
        do {
            try await AppStore.sync()
            #if os(iOS)
            // A receipt refresh may fail while a valid IAP is still available.
            // Scan both sources before deciding whether restoration succeeded.
            if checksPaidAppPurchase { _ = try? await AppTransaction.refresh() }
            #endif
            await refreshAccess()
            if access == .locked { message = "No active membership or lifetime purchase was found for this Apple Account." }
        } catch {
            message = "Couldn’t restore purchases. \(error.localizedDescription)"
        }
    }

    #if DEBUG
    static var uiFixture: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-purchaseFixture"), arguments.indices.contains(index + 1) else { return nil }
        let value = arguments[index + 1]
        return ["locked", "paid", "lifetime"].contains(value) ? value : nil
    }
    #endif
}
