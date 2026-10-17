import Foundation

/// Stores request attempts, never assumes that StoreKit displayed a prompt or that a review was left.
struct ReviewPromptPolicy {
    static let reviewedKey = "hasAlreadyReviewed"
    static let onboardingKey = "hasCompletedOnboarding"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func shouldRequest(afterOnboarding: Bool, now: Date = .now, randomValue: Double = Double.random(in: 0..<1)) -> Bool {
        guard !defaults.bool(forKey: Self.reviewedKey) else { return false }
        let attempts = requestDates.filter { now.timeIntervalSince($0) < 365 * 86_400 }
        guard attempts.count < 3 else { return false }
        if let last = attempts.max(), now.timeIntervalSince(last) < 120 * 86_400 { return false }
        return afterOnboarding || randomValue < 0.25
    }

    func recordRequest(now: Date = .now) {
        let recent = requestDates.filter { now.timeIntervalSince($0) < 365 * 86_400 }
        defaults.set(recent + [now], forKey: "reviewRequestDates")
    }

    private var requestDates: [Date] {
        defaults.array(forKey: "reviewRequestDates") as? [Date] ?? []
    }
}
