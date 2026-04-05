import Foundation

enum LifetimeUpgradeOfferKind: String, Codable, Equatable {
    case monthlyToLifetime = "monthly_to_lifetime"
    case yearlyToLifetime = "yearly_to_lifetime"
}

struct LifetimeUpgradeOffer: Codable, Equatable {
    let kind: LifetimeUpgradeOfferKind
    let discountedPriceLabel: String
    let isCodeAvailable: Bool
}

struct AccessStatus: Codable, Equatable {
    let plan: String
    let isUnlimited: Bool
    let isTrial: Bool
    let unlimitedSource: String?
    let trialEndsAt: String?
    let daysLeft: Int?
    let todayUsed: Int
    let todayLimit: Int?
    let dailyResetAt: String
    let purchaseDate: String?
    let subscriptionExpiresAt: String?
    let storeProductId: String?
    let lifetimeUpgradeOffer: LifetimeUpgradeOffer?

    var isFree: Bool {
        !isUnlimited && !isTrial
    }
}

struct AccessStatusResponse: Codable {
    let userId: String?
    let email: String?
    let accessStatus: AccessStatus
}
