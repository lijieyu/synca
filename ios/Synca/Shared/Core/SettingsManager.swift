import Foundation

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let macOSDefaultSavePathKey = "macOSDefaultSavePath"
    private let macOSDefaultSaveBookmarkKey = "macOSDefaultSaveBookmark"

    @Published var macOSDefaultSavePath: URL?

    private init() {
        macOSDefaultSavePath = resolveStoredSavePath()
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    func setMacOSDefaultSavePath(_ url: URL?) {
        macOSDefaultSavePath = url

        guard let url else {
            UserDefaults.standard.removeObject(forKey: macOSDefaultSavePathKey)
            UserDefaults.standard.removeObject(forKey: macOSDefaultSaveBookmarkKey)
            return
        }

        UserDefaults.standard.set(url.path, forKey: macOSDefaultSavePathKey)

        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: macOSDefaultSaveBookmarkKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: macOSDefaultSaveBookmarkKey)
            print("[settings] Failed to persist security-scoped bookmark: \(error)")
        }
    }

    func withSecurityScopedAccess<T>(to url: URL, perform: () throws -> T) rethrows -> T {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        return try perform()
    }

    private func resolveStoredSavePath() -> URL? {
        if let bookmarkData = UserDefaults.standard.data(forKey: macOSDefaultSaveBookmarkKey) {
            do {
                var isStale = false
                let url = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
                if isStale {
                    setMacOSDefaultSavePath(url)
                }
                return url
            } catch {
                print("[settings] Failed to resolve security-scoped bookmark: \(error)")
            }
        }

        if let path = UserDefaults.standard.string(forKey: macOSDefaultSavePathKey) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}
