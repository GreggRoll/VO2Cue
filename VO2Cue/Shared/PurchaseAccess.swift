import Foundation

enum PurchaseConfiguration {
    static let monthlyID = "com.gregadams.vo2cue.monthly"
    static let lifetimeID = "com.gregadams.vo2cue.lifetime"
    static let productIDs = [monthlyID, lifetimeID]

    // RELEASE SETUP: set the UTC instant at which the download price becomes Free.
    // Leave nil while the app is still paid. A nil cutoff preserves paid-app access
    // for verified production downloads; sandbox/TestFlight never qualify as buyers.
    // Coordinate this with App Store Connect's price schedule before shipping.
    static let paidDownloadCutoff: Date? = nil

    static let privacyURL = URL(string: "https://greggroll.github.io/VO2Cue/privacy")!
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

enum PaidAppAccessPolicy {
    static func qualifies(originalPurchaseDate: Date, isProduction: Bool, cutoff: Date?) -> Bool {
        guard isProduction else { return false }
        guard let cutoff else { return true } // Still a paid download.
        return originalPurchaseDate < cutoff
    }
}

/// Paired-phone access lets the Watch work independently after syncing. Monthly
/// access has an expiry; lifetime/paid-app access has none. No install-date guesses.
struct WatchPurchaseAccess: Codable, Equatable {
    var isUnlocked: Bool
    var expiresAt: Date?

    func allowsWorkout(at date: Date = .now) -> Bool {
        isUnlocked && (expiresAt.map { $0 > date } ?? true)
    }
}
