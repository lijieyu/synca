import SwiftUI

struct StoreRelease: Decodable { let version: String; let storeURL: String }
struct StoreReleases: Decodable { let ios: StoreRelease; let macos: StoreRelease }
enum AppVersion {
    static func isNewer(_ next: String, than current: String) -> Bool {
        func parts(_ value: String) -> [Int]? {
            let items = value.split(separator: ".", omittingEmptySubsequences: false)
            guard items.count == 3 else { return nil }
            var result: [Int] = []
            for item in items {
                guard !item.isEmpty, item.allSatisfy({ $0.isASCII && $0.isNumber }),
                      (item == "0" || item.first != "0"), let number = Int(item) else { return nil }
                result.append(number)
            }
            return result
        }
        guard let a = parts(next), let b = parts(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }
}
@MainActor final class StoreUpdateManager: ObservableObject {
    static let shared = StoreUpdateManager()
    static let storeURL = URL(string: "https://apps.apple.com/app/id6761647007")!
    @Published var release: StoreRelease?
    @Published var status = "updates.idle"
    @Published var snoozed = false
    private var lastCheck: Date?
    private var checking = false
    func check(manual: Bool = false) async {
        guard !checking else { return }
        if !manual, let lastCheck, Date().timeIntervalSince(lastCheck) < 86400 { return }
        checking = true; defer { checking = false }
        status = "updates.checking"
        do {
            let catalog = try await APIClient.shared.getStoreReleases()
            #if os(macOS)
            let candidate = catalog.macos
            #else
            let candidate = catalog.ios
            #endif
            guard candidate.storeURL == Self.storeURL.absoluteString else { throw APIError.invalidResponse }
            let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            lastCheck = Date()
            release = AppVersion.isNewer(candidate.version, than: current) ? candidate : nil
            let until = UserDefaults.standard.double(forKey: "update-snooze-\(candidate.version)")
            snoozed = !manual && until > Date().timeIntervalSince1970
            status = release == nil ? "updates.current" : "updates.available"
        } catch { status = "updates.error" }
    }
    func later() {
        if let release { UserDefaults.standard.set(Date().timeIntervalSince1970 + 86400, forKey: "update-snooze-\(release.version)") }
        snoozed = true
    }
}
struct StoreUpdateNotice: View {
    var manual = false
    @ObservedObject private var manager = StoreUpdateManager.shared
    var body: some View {
        if manual || (manager.release != nil && !manager.snoozed) {
            VStack(alignment: .leading, spacing: 10) {
                if let release = manager.release {
                    Text(String(format: String(syncaLocalized: "updates.available_native"), release.version)).font(.callout)
                    HStack {
                        Link("updates.store", destination: StoreUpdateManager.storeURL)
                        if !manual { Button("updates.later") { manager.later() } }
                    }.frame(minHeight: 44)
                } else { Text(LocalizedStringKey(manager.status)).font(.footnote).foregroundStyle(.secondary) }
                if manual { Button("updates.check") { Task { await manager.check(manual: true) } }.disabled(manager.status == "updates.checking") }
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
             .accessibilityElement(children: .contain)
        }
    }
}
