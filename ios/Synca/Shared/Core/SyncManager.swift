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
    @Published var isRefreshing = false
    @Published var errorMessage: String?
    @Published var sessionExpired = false  // #7: 401 踢出到登录页

    private var pollTimer: Timer?
    private var lastSyncTimestamp: String?
    private let api = APIClient.shared

    private init() {}

    // MARK: - Full Sync (新设备登录时全量同步)

    func fullSync() async {
        guard api.isAuthenticated else { return }
        isLoading = messages.isEmpty // only show loading on first load
        errorMessage = nil

        do {
            let allMessages = try await api.listMessages()
            messages = allMessages
            unclearedCount = allMessages.filter { !$0.isCleared }.count
            lastSyncTimestamp = allMessages.compactMap(\.updatedAt).max()
        } catch {
            handleError(error, context: "同步")
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
            handleError(error, context: "同步", silent: true)
        }
    }

    // MARK: - Pull to Refresh (#5)

    func refresh() async {
        isRefreshing = true
        await fullSync()
        isRefreshing = false
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
            handleError(error, context: "发送")
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
            handleError(error, context: "图片发送")
        }

        isSending = false
    }

    // #2: 批量发送多张图片
    func sendImages(_ imageDatas: [Data]) async {
        isSending = true

        for imageData in imageDatas {
            do {
                let message = try await api.sendImageMessage(
                    imageData: imageData,
                    sourceDevice: currentDeviceName()
                )
                messages.append(message)
                unclearedCount += 1
                lastSyncTimestamp = message.updatedAt
            } catch {
                handleError(error, context: "图片发送")
            }
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
            handleError(error, context: "清理")
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
            handleError(error, context: "清理")
        }
    }

    // MARK: - Helpers

    func reset() {
        stopPolling()
        messages = []
        unclearedCount = 0
        lastSyncTimestamp = nil
        sessionExpired = false
    }

    // #7: 统一错误处理，401 时踢出到登录页
    private func handleError(_ error: Error, context: String, silent: Bool = false) {
        if error is CancellationError { return }

        if case APIError.unauthorized = error {
            sessionExpired = true
            api.clearToken()
            return
        }

        if !silent {
            errorMessage = "\(context)失败: \(error.localizedDescription)"
        } else {
            print("[sync] \(context) failed: \(error.localizedDescription)")
        }
    }

    func currentDeviceName() -> String {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Unknown"
        #endif
    }
}
