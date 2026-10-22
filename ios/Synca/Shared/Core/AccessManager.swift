import Foundation

@MainActor
final class AccessManager: ObservableObject {
    static let shared = AccessManager()

    @Published var status: AccessStatus?
    @Published var isLoading = false
    @Published var showAccessCenter = false
    @Published var shouldHighlightUpgrade = false

    private var refreshID = UUID()

    private init() {}

    func refresh() async {
        guard APIClient.shared.isAuthenticated else {
            clear()
            return
        }

        let requestID = UUID()
        refreshID = requestID
        isLoading = true
        defer { if refreshID == requestID { isLoading = false } }

        do {
            let result = try await APIClient.shared.getAccessStatus()
            guard refreshID == requestID, APIClient.shared.isAuthenticated else { return }
            status = result
        } catch {
            print("[access] refresh failed: \(error)")
        }
    }

    func apply(_ newStatus: AccessStatus) {
        refreshID = UUID()
        isLoading = false
        status = newStatus
    }

    func presentUpgrade(using newStatus: AccessStatus?) {
        if let newStatus {
            status = newStatus
        }
        shouldHighlightUpgrade = true
        showAccessCenter = true
    }

    func clear() {
        refreshID = UUID()
        status = nil
        isLoading = false
        showAccessCenter = false
        shouldHighlightUpgrade = false
    }

    func clearUpgradeHighlight() {
        shouldHighlightUpgrade = false
    }
}
