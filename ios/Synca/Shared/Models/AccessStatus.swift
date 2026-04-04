import Foundation

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

    var isFree: Bool {
        !isUnlimited && !isTrial
    }
}

struct AccessStatusResponse: Codable {
    let userId: String?
    let email: String?
    let accessStatus: AccessStatus
}
