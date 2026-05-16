import Foundation

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let macOSDefaultSavePathKey = "macOSDefaultSavePath"
    private let macOSDefaultSaveBookmarkKey = "macOSDefaultSaveBookmark"
    private let messageListLayoutModeKey = "messageListLayoutMode"

    @Published var macOSDefaultSavePath: URL?
    @Published var messageListLayoutMode: MessageListLayoutMode

    private init() {
        messageListLayoutMode = MessageListLayoutMode(rawValue: UserDefaults.standard.string(forKey: messageListLayoutModeKey) ?? "") ?? .single
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

        #if os(macOS)
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: macOSDefaultSaveBookmarkKey)
        } catch {
            UserDefaults.standard.removeObject(forKey: macOSDefaultSaveBookmarkKey)
            print("[settings] Failed to persist security-scoped bookmark: \(error)")
        }
        #else
        UserDefaults.standard.removeObject(forKey: macOSDefaultSaveBookmarkKey)
        #endif
    }

    func withSecurityScopedAccess<T>(to url: URL, perform: () throws -> T) rethrows -> T {
        #if os(macOS)
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }
        #endif
        return try perform()
    }

    func selectedMessageCategoryId(for userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return UserDefaults.standard.string(forKey: selectedMessageCategoryKey(for: userId))
    }

    func setSelectedMessageCategoryId(_ categoryId: String?, for userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        let key = selectedMessageCategoryKey(for: userId)
        if let categoryId, !categoryId.isEmpty {
            UserDefaults.standard.set(categoryId, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func defaultSendCategoryId(for userId: String?) -> String? {
        guard let userId, !userId.isEmpty else { return nil }
        return UserDefaults.standard.string(forKey: defaultSendCategoryKey(for: userId))
    }

    func setDefaultSendCategoryId(_ categoryId: String?, for userId: String?) {
        guard let userId, !userId.isEmpty else { return }
        let key = defaultSendCategoryKey(for: userId)
        if let categoryId, !categoryId.isEmpty {
            UserDefaults.standard.set(categoryId, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func setMessageListLayoutMode(_ mode: MessageListLayoutMode) {
        messageListLayoutMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: messageListLayoutModeKey)
    }

    private func selectedMessageCategoryKey(for userId: String) -> String {
        "selectedMessageCategoryId.\(userId)"
    }

    private func defaultSendCategoryKey(for userId: String) -> String {
        "defaultSendMessageCategoryId.\(userId)"
    }

    private func resolveStoredSavePath() -> URL? {
        #if os(macOS)
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
        #endif

        if let path = UserDefaults.standard.string(forKey: macOSDefaultSavePathKey) {
            return URL(fileURLWithPath: path)
        }

        return nil
    }
}

enum MessageListLayoutMode: String {
    case single
    case tiled
}
