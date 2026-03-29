import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case error(String)
        
        var isSyncing: Bool { self == .syncing }
    }

    @Published var messages: [SyncaMessage] = []
    @Published var unclearedCount: Int = 0
    @Published var isLoading = false
    @Published var isSending = false
    @Published var isRefreshing = false
    @Published var syncStatus: SyncStatus = .idle // #5: 同步状态反馈
    @Published var lastRefreshDate: Date?       // #5: 上次同步时间
    @Published var errorMessage: String?
    @Published var sessionExpired = false

    private var pollTimer: Timer?
    private var lastSyncTimestamp: String?
    private let api = APIClient.shared
    private var statusResetTask: Task<Void, Never>?

    private init() {}

    // MARK: - Full Sync

    func fullSync() async {
        guard api.isAuthenticated else { return }
        isLoading = messages.isEmpty
        errorMessage = nil
        updateStatus(.syncing)

        do {
            let allMessages = try await api.listMessages()
            messages = allMessages
            unclearedCount = allMessages.filter { !$0.isCleared }.count
            lastSyncTimestamp = allMessages.compactMap(\.updatedAt).max()
            lastRefreshDate = Date()
            updateStatus(.success)
        } catch {
            handleError(error, context: "同步")
            updateStatus(.error(error.localizedDescription))
        }

        isLoading = false
    }

    // MARK: - Incremental Sync

    func incrementalSync() async {
        guard api.isAuthenticated else { return }
        updateStatus(.syncing)

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
                messages.sort { $0.createdAt < $1.createdAt }
                lastSyncTimestamp = messages.compactMap(\.updatedAt).max() ?? lastSyncTimestamp
                lastRefreshDate = Date()
            }
            unclearedCount = messages.filter { !$0.isCleared }.count
            updateStatus(.success)
        } catch {
            handleError(error, context: "同步", silent: true)
            updateStatus(.error(error.localizedDescription))
        }
    }

    // MARK: - Pull to Refresh

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

    // MARK: - Status Helper
    
    private func updateStatus(_ status: SyncStatus) {
        syncStatus = status
        statusResetTask?.cancel()
        
        // 成功或错误状态在 3 秒后重置回 idle
        if status != .syncing && status != .idle {
            statusResetTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    syncStatus = .idle
                }
            }
        }
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
            lastRefreshDate = Date()
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
            lastRefreshDate = Date()
        } catch {
            handleError(error, context: "图片发送")
        }

        isSending = false
    }

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
        lastRefreshDate = Date()
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
        syncStatus = .idle
        lastRefreshDate = nil
    }

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
