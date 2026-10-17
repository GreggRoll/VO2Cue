import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(PurchaseStore.self) private var purchases
    @State private var selectedPlan: Plan = .lifetime
    @State private var showingFeedback = false
    var onReviewIntroduction: (() -> Void)?

    private enum Plan: String, CaseIterable, Identifiable {
        case lifetime, monthly
        var id: Self { self }
        var productID: String { self == .lifetime ? PurchaseConfiguration.lifetimeID : PurchaseConfiguration.monthlyID }
        var title: String { self == .lifetime ? "Lifetime access" : "Monthly" }
        var detail: String { self == .lifetime ? "Best value. Pay once." : "Cancel anytime." }
        var billing: String { self == .lifetime ? "one-time purchase" : "per month" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("VO2Cue").font(.title3.bold())
                    Spacer()
                    Label("FULL ACCESS", systemImage: "lock.fill")
                        .font(.caption.bold()).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your fitter future\nstarts here.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .accessibilityAddTraits(.isHeader).accessibilityIdentifier("paywallTitle")
                    Text("Eyes-free interval coaching. One simple habit for a fitter you and a healthier future.")
                        .font(.body).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 13) {
                    included("Eyes-free cues on iPhone & Apple Watch")
                    included("Norwegian 4×4 & unlimited custom profiles")
                    included("Workout history & optional Apple Health saving")
                }
                VStack(spacing: 12) {
                    ForEach(Plan.allCases) { plan in planButton(plan) }
                }
                if let message = purchases.message {
                    Text(message).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("purchaseMessage")
                }
                HStack {
                    Button(purchases.isRestoring ? "Restoring…" : "Restore purchases") {
                        Task { await purchases.restore() }
                    }
                    .disabled(purchases.isBusy)
                    Spacer()
                    if purchases.access == .unavailable || purchases.products.count < 2 {
                        Button("Try again") { Task { await purchases.start() } }
                            .disabled(purchases.isBusy || purchases.isLoadingProducts)
                    }
                }
                .font(.subheadline)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Already bought VO2Cue as a paid app? Your lifetime access is included. Restore using the Apple Account you purchased with.")
                    Text("Monthly membership renews automatically unless canceled at least 24 hours before the current period ends. Manage or cancel in App Store account settings. Lifetime access is a single payment with no renewal.")
                    HStack(spacing: 22) {
                        Link("Terms of Use", destination: PurchaseConfiguration.termsURL)
                        Link("Privacy Policy", destination: PurchaseConfiguration.privacyURL)
                    }
                    if let onReviewIntroduction { Button("Review introduction", action: onReviewIntroduction) }
                    Button("Need help?") { showingFeedback = true }
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity).padding(24)
        }
        .background(.background).interactiveDismissDisabled()
        .safeAreaInset(edge: .bottom) {
            purchaseAction
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(.background)
        }
        .sheet(isPresented: $showingFeedback) { FeedbackView() }
    }

    private func included(_ title: String) -> some View {
        Label(title, systemImage: "checkmark.circle.fill").font(.subheadline)
    }

    private func planButton(_ plan: Plan) -> some View {
        Button { selectedPlan = plan } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selectedPlan == plan ? "largecircle.fill.circle" : "circle")
                    .font(.title2).foregroundStyle(selectedPlan == plan ? OnboardingStyle.accent : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(plan.title).font(.headline)
                    Text(plan.detail).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(price(for: plan)).font(.title2.bold())
                    Text(plan.billing).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(OnboardingStyle.card, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(selectedPlan == plan ? OnboardingStyle.accent : .clear, lineWidth: 2)
            }
        }
        .buttonStyle(.plain).disabled(purchases.isBusy)
        .accessibilityIdentifier("plan_\(plan.rawValue)")
        .accessibilityAddTraits(selectedPlan == plan ? .isSelected : [])
    }

    private func price(for plan: Plan) -> String {
        if let product = purchases.product(id: plan.productID) { return product.displayPrice }
        #if DEBUG
        if PurchaseStore.uiFixture != nil { return plan == .lifetime ? "$19.99" : "$1.99" }
        #endif
        return purchases.isLoadingProducts ? "Loading price…" : "Currently unavailable"
    }

    private var purchaseAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            if purchases.access == .checking {
                HStack { ProgressView(); Text("Checking your existing access…") }.font(.subheadline)
            }
            OnboardingPrimaryButton(title: actionTitle, isBusy: purchases.isPurchasing) {
                guard let product = purchases.product(id: selectedPlan.productID) else { return }
                Task { await purchases.purchase(product) }
            }
            .disabled(!isPurchaseAvailable)
            .opacity(isPurchaseAvailable ? 1 : 0.55)
            .accessibilityIdentifier("purchasePlan")
            Text(selectedPlan == .lifetime ? "One payment. Full access. No recurring charge." : "\(price(for: .monthly)) per month, billed monthly. Cancel anytime.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var isPurchaseAvailable: Bool {
        #if DEBUG
        if PurchaseStore.uiFixture != nil { return true }
        #endif
        return purchases.canPurchase && purchases.product(id: selectedPlan.productID) != nil
    }

    private var actionTitle: String {
        #if DEBUG
        if PurchaseStore.uiFixture != nil {
            return selectedPlan == .lifetime ? "Unlock for $19.99" : "Subscribe for $1.99/month"
        }
        #endif
        guard let product = purchases.product(id: selectedPlan.productID) else { return "Unlock VO2Cue" }
        return selectedPlan == .lifetime ? "Unlock for \(product.displayPrice)" : "Subscribe for \(product.displayPrice)/month"
    }
}
