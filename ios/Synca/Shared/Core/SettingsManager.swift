import Foundation
import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case system, simplifiedChinese = "zh-Hans", traditionalChinese = "zh-Hant", english = "en"
    var id: String { rawValue }
    var labelKey: String {
        switch self {
        case .system: return "settings.follow_system"
        case .simplifiedChinese: return "settings.language_simplified"
        case .traditionalChinese: return "settings.language_traditional"
        case .english: return "settings.language_english"
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    var labelKey: String { "settings.appearance_\(rawValue)" }
}

/// One source for Foundation/AppKit strings as well as SwiftUI's locale environment.
/// Reading the preference here also supports errors produced outside the main actor.
enum AppLocalization {
    static let languageKey = "appLanguage"
    static var identifier: String {
        let selection = AppLanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .system
        if selection != .system { return selection.rawValue }
        return Bundle.preferredLocalizations(from: ["zh-Hans", "zh-Hant", "en"], forPreferences: Locale.preferredLanguages).first ?? "en"
    }
    static var locale: Locale { Locale(identifier: identifier) }
    static var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: identifier, ofType: "lproj"), let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
    static func string(_ key: String) -> String { bundle.localizedString(forKey: key, value: nil, table: nil) }
}

extension String {
    init(syncaLocalized key: String.LocalizationValue, bundle: Bundle = .main) {
        self.init(localized: key, bundle: bundle == .main ? AppLocalization.bundle : bundle, locale: AppLocalization.locale)
    }
}

private struct AppPreferencesModifier: ViewModifier {
    @ObservedObject private var settings = SettingsManager.shared
    func body(content: Content) -> some View {
        content.environment(\.locale, settings.locale)
            .preferredColorScheme(settings.appAppearance.colorScheme)
    }
}

extension View {
    /// Presentations need their own observing boundary; AppKit can otherwise snapshot the parent environment.
    func syncaPreferences() -> some View { modifier(AppPreferencesModifier()) }
}

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private let macOSDefaultSavePathKey = "macOSDefaultSavePath"
    private let macOSDefaultSaveBookmarkKey = "macOSDefaultSaveBookmark"
    private let messageListLayoutModeKey = "messageListLayoutMode"

    @Published var macOSDefaultSavePath: URL?
    @Published var messageListLayoutMode: MessageListLayoutMode
    @Published var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: AppLocalization.languageKey) }
    }
    @Published var appAppearance: AppAppearance {
        didSet { UserDefaults.standard.set(appAppearance.rawValue, forKey: "appAppearance") }
    }
    @Published var asksForDownloadLocation: Bool {
        didSet { UserDefaults.standard.set(asksForDownloadLocation, forKey: "asksForDownloadLocation") }
    }
    var locale: Locale { AppLocalization.locale }

    private init() {
        appLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: AppLocalization.languageKey) ?? "") ?? .system
        appAppearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appAppearance") ?? "") ?? .system
        asksForDownloadLocation = UserDefaults.standard.bool(forKey: "asksForDownloadLocation")
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
