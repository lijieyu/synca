import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    @Published var messages: [SyncaMessage] = []
    @Published var unclearedCount: Int = 0
    @Published var isLoading = false
    @Published var isSending = false
    @Published var errorMessage: String?

    private var pollTimer: Timer?
    private var lastSyncTimestamp: String?
    private let api = APIClient.shared

    private init() {}

    // MARK: - Full Sync

    func fullSync() async {
        guard api.isAuthenticated else { return }
        isLoading = messages.isEmpty // only show loading on first load
        errorMessage = nil

        do {
            let allMessages = try await api.listMessages()
            messages = allMessages
            unclearedCount = allMessages.filter { !$0.isCleared }.count
            lastSyncTimestamp = allMessages.last?.updatedAt
        } catch {
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
    }

    // MARK: - Incremental Sync

    func incrementalSync() async {
        guard api.isAuthenticated else { return }

        do {
            let since = lastSyncTimestamp
            let newMessages = try await api.listMessages(since: since)

            if !newMessages.isEmpty {
                for msg in newMessages {
                    if let index = messages.firstIndex(where: { $0.id == msg.id }) {
                        messages[index] = msg
                    } else {
                        messages.append(msg)
                    }
                }
                // Re-sort by createdAt
                messages.sort { $0.createdAt < $1.createdAt }
                lastSyncTimestamp = messages.compactMap(\.updatedAt).max() ?? lastSyncTimestamp
            }

            unclearedCount = messages.filter { !$0.isCleared }.count
        } catch {
            // Silent fail for background sync
            print("[sync] incremental sync failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.incrementalSync()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Send Messages

    func sendText(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSending = true

        do {
            let message = try await api.sendTextMessage(
                text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceDevice: currentDeviceName()
            )
            messages.append(message)
            unclearedCount += 1
            lastSyncTimestamp = message.updatedAt
        } catch {
            errorMessage = "发送失败: \(error.localizedDescription)"
        }

        isSending = false
    }

    func sendImage(_ imageData: Data) async {
        isSending = true

        do {
            let message = try await api.sendImageMessage(
                imageData: imageData,
                sourceDevice: currentDeviceName()
            )
            messages.append(message)
            unclearedCount += 1
            lastSyncTimestamp = message.updatedAt
        } catch {
            errorMessage = "图片发送失败: \(error.localizedDescription)"
        }

        isSending = false
    }

    // MARK: - Clear

    func clearMessage(_ id: String) async {
        do {
            try await api.clearMessage(id: id)
            if let index = messages.firstIndex(where: { $0.id == id }) {
                messages[index].isCleared = true
                messages[index].updatedAt = Date().ISO8601Format()
            }
            unclearedCount = messages.filter { !$0.isCleared }.count
        } catch {
            errorMessage = "清理失败: \(error.localizedDescription)"
        }
    }

    func clearAll() async {
        do {
            _ = try await api.clearAllMessages()
            for i in messages.indices {
                messages[i].isCleared = true
            }
            unclearedCount = 0
        } catch {
            errorMessage = "清理失败: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    func reset() {
        stopPolling()
        messages = []
        unclearedCount = 0
        lastSyncTimestamp = nil
    }

    private func currentDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown"
        #endif
    }
}
