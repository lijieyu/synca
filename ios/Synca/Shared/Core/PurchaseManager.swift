import Foundation
import StoreKit
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum SyncaProductID: String, CaseIterable {
    case monthly = "org.haerth.synca.unlimited.monthly"
    case yearly = "org.haerth.synca.unlimited.yearly"
    case lifetime = "org.haerth.synca.unlimited.lifetime"

    static let allIDs = Set(allCases.map(\.rawValue))
}

@MainActor
final class PurchaseManager: ObservableObject {
    enum RestoreOutcome {
        case restoredPurchases
        case noPurchasesFound
    }

    static let shared = PurchaseManager()

    @Published private(set) var productsByID: [String: Product] = [:]
    @Published var isLoadingProducts = false
    @Published var purchasingProductID: String?
    @Published var isRestoring = false
    @Published var redeemingOfferKind: LifetimeUpgradeOfferKind?
    @Published var lastErrorMessage: String?
    @Published private(set) var introEligibilityByID: [String: Bool] = [:]

    private var updatesTask: Task<Void, Never>?

    private init() {
        updatesTask = observeTransactionUpdates()
    }

    deinit {
        updatesTask?.cancel()
    }

    var yearlyProduct: Product? {
        productsByID[SyncaProductID.yearly.rawValue]
    }

    var monthlyProduct: Product? {
        productsByID[SyncaProductID.monthly.rawValue]
    }

    var lifetimeProduct: Product? {
        productsByID[SyncaProductID.lifetime.rawValue]
    }

    func loadProducts() async {
        if !productsByID.isEmpty {
            await refreshIntroEligibility(for: Array(productsByID.values))
            return
        }
        lastErrorMessage = nil
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: Array(SyncaProductID.allIDs))
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            await refreshIntroEligibility(for: products)
        } catch {
            lastErrorMessage = String(localized: "access.purchase_fetch_failed", bundle: .main)
            print("[purchase] loadProducts failed: \(error)")
        }
    }

    @discardableResult
    func purchase(_ productID: SyncaProductID) async -> Bool {
        lastErrorMessage = nil
        do {
            try await loadProductsIfNeeded()
            guard let product = productsByID[productID.rawValue] else {
                lastErrorMessage = String(localized: "access.purchase_unavailable", bundle: .main)
                return false
            }

            let accountToken = try currentAccountToken()
            purchasingProductID = product.id
            defer { purchasingProductID = nil }

            let result = try await product.purchase(options: [.appAccountToken(accountToken)])
            switch result {
            case .success(let verification):
                let transaction = try verifiedTransaction(from: verification)
                let accessStatus = try await APIClient.shared.syncPurchases(signedTransactions: [verification.jwsRepresentation])
                AccessManager.shared.apply(accessStatus)
                await transaction.finish()
                return true
            case .pending:
                lastErrorMessage = String(localized: "access.purchase_pending", bundle: .main)
                return false
            case .userCancelled:
                return false
            @unknown default:
                lastErrorMessage = String(localized: "access.purchase_failed", bundle: .main)
                return false
            }
        } catch {
            guard !isUserCancelledPurchase(error) else {
                return false
            }
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "access.purchase_failed", bundle: .main)
            print("[purchase] purchase failed: \(error)")
            return false
        }
    }

    func restorePurchases() async {
        lastErrorMessage = nil
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await AppStore.sync()
            let outcome = try await syncLatestTransactions()
            switch outcome {
            case .restoredPurchases:
                lastErrorMessage = String(localized: "access.restore_success", bundle: .main)
            case .noPurchasesFound:
                lastErrorMessage = String(localized: "access.restore_no_purchases", bundle: .main)
            }
        } catch {
            guard !isUserCancelledPurchase(error) else {
                return
            }
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "access.restore_failed", bundle: .main)
            print("[purchase] restore failed: \(error)")
        }
    }

    @discardableResult
    func redeemLifetimeUpgradeOffer(_ offer: LifetimeUpgradeOffer) async -> Bool {
        lastErrorMessage = nil
        redeemingOfferKind = offer.kind
        defer { redeemingOfferKind = nil }

        do {
            let response = try await APIClient.shared.requestLifetimeUpgradeOfferCode(kind: offer.kind)
            copyOfferCodeToPasteboard(response.code)
            try await presentOfferCodeRedeemSheet()
            lastErrorMessage = String(localized: "access.lifetime_offer_copied", bundle: .main)
            return true
        } catch {
            guard !isUserCancelledPurchase(error) else {
                return false
            }
            lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? String(localized: "access.offer_unavailable", bundle: .main)
            print("[purchase] redeem offer failed: \(error)")
            return false
        }
    }

    func syncLatestTransactions() async throws -> RestoreOutcome {
        guard APIClient.shared.isAuthenticated else { return .noPurchasesFound }

        var signedTransactions: [String] = []
        for productID in SyncaProductID.allCases.map(\.rawValue) {
            guard let latest = await Transaction.latest(for: productID) else { continue }
            if case .verified = latest {
                signedTransactions.append(latest.jwsRepresentation)
            }
        }

        if signedTransactions.isEmpty {
            let status = try await APIClient.shared.getAccessStatus()
            AccessManager.shared.apply(status)
            return .noPurchasesFound
        }

        let status = try await APIClient.shared.syncPurchases(signedTransactions: signedTransactions)
        AccessManager.shared.apply(status)
        return .restoredPurchases
    }

    private func loadProductsIfNeeded() async throws {
        if productsByID.isEmpty {
            await loadProducts()
        }
        if productsByID.isEmpty {
            throw PurchaseError.productsUnavailable
        }
    }

    private func currentAccountToken() throws -> UUID {
        guard let userId = APIClient.shared.currentUserId,
              let uuid = UUID(uuidString: userId) else {
            throw PurchaseError.missingAccountToken
        }
        return uuid
    }

    private func verifiedTransaction(from verification: VerificationResult<Transaction>) throws -> Transaction {
        switch verification {
        case .verified(let transaction):
            return transaction
        case .unverified:
            throw PurchaseError.unverifiedTransaction
        }
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await verification in Transaction.updates {
                do {
                    guard await MainActor.run(body: { APIClient.shared.isAuthenticated }) else { continue }
                    let transaction = try await MainActor.run { try self.verifiedTransaction(from: verification) }
                    guard SyncaProductID.allIDs.contains(transaction.productID) else {
                        await transaction.finish()
                        continue
                    }

                    let status = try await APIClient.shared.syncPurchases(signedTransactions: [verification.jwsRepresentation])
                    await MainActor.run {
                        AccessManager.shared.apply(status)
                    }
                    await transaction.finish()
                } catch {
                    print("[purchase] transaction update handling failed: \(error)")
                }
            }
        }
    }

    private func isUserCancelledPurchase(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == SKErrorDomain && nsError.code == SKError.paymentCancelled.rawValue {
            return true
        }

        let localized = nsError.localizedDescription.lowercased()
        return localized.contains("request canceled") || localized.contains("request cancelled")
    }

    private func refreshIntroEligibility(for products: [Product]) async {
        var eligibility: [String: Bool] = [:]
        for product in products {
            guard let subscription = product.subscription,
                  subscription.introductoryOffer != nil else {
                continue
            }
            eligibility[product.id] = await subscription.isEligibleForIntroOffer
        }
        introEligibilityByID = eligibility
    }

    func isIntroOfferEligible(for productID: SyncaProductID) -> Bool {
        introEligibilityByID[productID.rawValue] == true
    }

    private func presentOfferCodeRedeemSheet() async throws {
        #if canImport(UIKit)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) else {
            throw PurchaseError.missingRedeemContext
        }
        try await AppStore.presentOfferCodeRedeemSheet(in: scene)
        #elseif canImport(AppKit)
        guard #available(macOS 15.0, *) else {
            throw PurchaseError.missingRedeemContext
        }
        guard let controller = NSApp.keyWindow?.contentViewController ?? NSApp.windows.first?.contentViewController else {
            throw PurchaseError.missingRedeemContext
        }
        try await AppStore.presentOfferCodeRedeemSheet(from: controller)
        #endif
    }

    private func copyOfferCodeToPasteboard(_ code: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = code
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #endif
    }
}

enum PurchaseError: LocalizedError {
    case missingAccountToken
    case productsUnavailable
    case unverifiedTransaction
    case missingRedeemContext

    var errorDescription: String? {
        switch self {
        case .missingAccountToken:
            return String(localized: "access.purchase_account_missing", bundle: .main)
        case .productsUnavailable:
            return String(localized: "access.purchase_unavailable", bundle: .main)
        case .unverifiedTransaction:
            return String(localized: "access.purchase_verification_failed", bundle: .main)
        case .missingRedeemContext:
            return String(localized: "access.offer_unavailable", bundle: .main)
        }
    }
}
