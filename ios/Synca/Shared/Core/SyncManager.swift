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
    @Published var syncStatus: SyncStatus = .idle 
    @Published var lastRefreshDate: Date?       
    @Published var errorMessage: String?
    @Published var sessionExpired = false

    var imageMessages: [SyncaMessage] {
        messages.filter { $0.type == .image && !$0.isDeleted }
    }

    private var pollTimer: Timer?
    private var lastSyncTimestamp: String?
    private let api = APIClient.shared
    private var statusResetTask: Task<Void, Never>?
    private var isSyncingInternal = false // Concurrency lock
    private var isManualRefresh = false

    private init() {}

    // MARK: - Full Sync

    func fullSync(manual: Bool = false) async {
        guard api.isAuthenticated else { return }
        guard !isSyncingInternal else { return }
        
        isSyncingInternal = true
        isLoading = messages.isEmpty && manual
        errorMessage = nil
        
        defer {
            isLoading = false
            isSyncingInternal = false
        }
        
        if manual { updateStatus(.syncing) }

        do {
            let allMessages = try await api.listMessages()
            messages = allMessages
            unclearedCount = allMessages.filter { !$0.isCleared }.count
            lastSyncTimestamp = allMessages.compactMap(\.updatedAt).max()
            lastRefreshDate = Date()
            if manual { updateStatus(.success) }
        } catch is CancellationError {
            // Ignore cancellation to avoid false error reports during scroll/pull
        } catch {
            handleError(error, context: "同步")
            if manual { updateStatus(.error(error.localizedDescription)) }
        }
    }

    // MARK: - Incremental Sync

    func incrementalSync(manual: Bool = false) async {
        guard api.isAuthenticated else { return }
        guard !isSyncingInternal else { return }
        
        isSyncingInternal = true
        defer { isSyncingInternal = false }
        
        if manual { updateStatus(.syncing) }

        do {
            let since = lastSyncTimestamp
            let newMessages = try await api.listMessages(since: since)

            if !newMessages.isEmpty {
                for msg in newMessages {
                    if msg.isDeleted {
                        messages.removeAll { $0.id == msg.id }
                        continue
                    }
                    
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
            if manual { updateStatus(.success) }
        } catch is CancellationError {
            // Ignore
        } catch {
            handleError(error, context: "同步", silent: !manual)
            if manual { updateStatus(.error(error.localizedDescription)) }
        }
    }

    // MARK: - Pull to Refresh

    func refresh() async {
        isRefreshing = true
        await fullSync(manual: true)
        isRefreshing = false
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                // 轮询采用静默模式
                await self?.incrementalSync(manual: false)
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
        var failureCount = 0
        
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
                failureCount += 1
                print("[send] 批量发送单张失败: \(error)")
            }
        }
        
        if failureCount > 0 {
            errorMessage = "批量发送完成，但有 \(failureCount) 张图片发送失败"
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

    func deleteMessage(_ id: String) async {
        do {
            try await api.deleteMessage(id: id)
            messages.removeAll { $0.id == id }
            unclearedCount = messages.filter { !$0.isCleared }.count
        } catch {
            handleError(error, context: "删除")
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

        // Trigger error haptic
        #if os(iOS)
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(.error)
        #endif

        print("[SyncManager] ERROR in \(context): \(error)")

        if case APIError.unauthorized = error {
            sessionExpired = true
            api.clearToken()
            return
        }

        let nsError = error as NSError
        let errorDescription = nsError.localizedDescription
        let errorCode = nsError.code
        let domain = nsError.domain
        
        let fullErrorMsg = "\(context)失败: \(errorDescription) (Code: \(errorCode), Domain: \(domain))"
        
        if !silent {
            errorMessage = fullErrorMsg
        }
        
        print("[SyncManager] ERROR in \(context): \(fullErrorMsg)")
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("[SyncManager] Underlying error: \(underlyingError)")
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
