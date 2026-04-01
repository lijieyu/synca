import Foundation

@MainActor
final class SyncDebugLogger {
    static let shared = SyncDebugLogger()

    private let logKey = "syncDebugLogs"
    private let maxEntries = 200

    private init() {}

    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let entry = "[sync-debug] \(timestamp) \(message)"
        print(entry)

        var logs = UserDefaults.standard.stringArray(forKey: logKey) ?? []
        logs.append(entry)
        if logs.count > maxEntries {
            logs.removeFirst(logs.count - maxEntries)
        }
        UserDefaults.standard.set(logs, forKey: logKey)
    }
}
