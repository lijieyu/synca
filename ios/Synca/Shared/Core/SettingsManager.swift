import Foundation

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()
    
    // macOS 默认保存路径
    @Published var macOSDefaultSavePath: URL? {
        didSet {
            if let url = macOSDefaultSavePath {
                UserDefaults.standard.set(url.path, forKey: "macOSDefaultSavePath")
            }
        }
    }
    
    private init() {
        if let path = UserDefaults.standard.string(forKey: "macOSDefaultSavePath") {
            macOSDefaultSavePath = URL(fileURLWithPath: path)
        } else {
            // 默认下载目录
            macOSDefaultSavePath = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
    }
}
