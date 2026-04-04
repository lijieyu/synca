import Foundation

@MainActor
final class AccessManager: ObservableObject {
    static let shared = AccessManager()

    @Published var status: AccessStatus?
    @Published var isLoading = false
    @Published var showAccessCenter = false
    @Published var shouldHighlightUpgrade = false

    private init() {}

    func refresh() async {
        guard APIClient.shared.isAuthenticated else {
            clear()
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            status = try await APIClient.shared.getAccessStatus()
        } catch {
            print("[access] refresh failed: \(error)")
        }
    }

    func apply(_ newStatus: AccessStatus) {
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
        status = nil
        isLoading = false
        showAccessCenter = false
        shouldHighlightUpgrade = false
    }

    func clearUpgradeHighlight() {
        shouldHighlightUpgrade = false
    }
}
