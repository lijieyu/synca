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
    @Published var hasCompletedInitialLoad = false
    @Published var isSending = false
    @Published var isRefreshing = false
    @Published var syncStatus: SyncStatus = .idle 
    @Published var lastRefreshDate: Date?       
    @Published var errorMessage: String?
    @Published var sessionExpired = false
    @Published var remoteAppendEvent = UUID()

    var imageMessages: [SyncaMessage] {
        messages.filter { $0.type == .image && !$0.isDeleted }
    }

    var orderedMessages: [SyncaMessage] {
        messages.sorted { m1, m2 in
            if m1.isCleared != m2.isCleared {
                return m1.isCleared
            }
            if m1.isCleared {
                return (m1.updatedAt ?? m1.createdAt) < (m2.updatedAt ?? m2.createdAt)
            }
            return m1.createdAt < m2.createdAt
        }
    }

    private var pollTimer: Timer?
    private var lastSyncTimestamp: String?
    private let api = APIClient.shared
    private var statusResetTask: Task<Void, Never>?
    private var isSyncingInternal = false // Concurrency lock
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var pollCycleCount = 0

    private init() {}

    // MARK: - Full Sync

    func fullSync(manual: Bool = false, showSuccessStatus: Bool = true) async {
        guard api.isAuthenticated else { return }
        guard !isSyncingInternal else { return }
        
        isSyncingInternal = true
        isLoading = messages.isEmpty && manual
        errorMessage = nil
        
        defer {
            isLoading = false
            hasCompletedInitialLoad = true
            isSyncingInternal = false
            resumeRefreshWaiters()
        }
        
        if manual { updateStatus(.syncing) }

        do {
            let existingIDs = Set(messages.map(\.id))
            let allMessages = try await api.listMessages()
            messages = allMessages
            unclearedCount = allMessages.filter { !$0.isCleared }.count
            lastSyncTimestamp = allMessages.compactMap(\.updatedAt).max()
            lastRefreshDate = Date()
            let appendedRemotely = hasCompletedInitialLoad && allMessages.contains { !existingIDs.contains($0.id) && !$0.isDeleted }
            if appendedRemotely {
                remoteAppendEvent = UUID()
            }
            if manual && showSuccessStatus { updateStatus(.success) }
        } catch {
            if isCancellationError(error) { return }
            handleError(error, contextKey: "sync.error_context.sync")
            if manual { updateStatus(.error(error.localizedDescription)) }
        }
    }

    // MARK: - Incremental Sync

    func incrementalSync(manual: Bool = false) async {
        guard api.isAuthenticated else { return }
        guard !isSyncingInternal else { return }
        
        isSyncingInternal = true
        defer {
            isSyncingInternal = false
            resumeRefreshWaiters()
        }
        
        if manual { updateStatus(.syncing) }

        do {
            let since = lastSyncTimestamp
            let newMessages = try await api.listMessages(since: since)
            var appendedRemotely = false

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
                        appendedRemotely = true
                    }
                }
                messages.sort { $0.createdAt < $1.createdAt }
                lastSyncTimestamp = messages.compactMap(\.updatedAt).max() ?? lastSyncTimestamp
                lastRefreshDate = Date()
            }
            unclearedCount = messages.filter { !$0.isCleared }.count
            if appendedRemotely && hasCompletedInitialLoad {
                remoteAppendEvent = UUID()
            }
            if manual { updateStatus(.success) }
        } catch {
            if isCancellationError(error) { return }
            handleError(error, contextKey: "sync.error_context.sync", silent: !manual)
            if manual { updateStatus(.error(error.localizedDescription)) }
        }
    }

    // MARK: - Pull to Refresh

    func refresh() async {
        await waitForCurrentSyncIfNeeded()
        isRefreshing = true
        stopPolling()
        await fullSync(manual: true)
        startPolling()
        isRefreshing = false
    }

    // MARK: - Polling

    func startPolling() {
        stopPolling()
        pollCycleCount = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.pollCycleCount += 1

                // 定期做一次全量同步，覆盖“删除历史”这类增量同步难以感知的变化
                if self.pollCycleCount % 3 == 0 {
                    await self.fullSync(manual: false, showSuccessStatus: false)
                } else {
                    await self.incrementalSync(manual: false)
                }
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        pollCycleCount = 0
    }

    // MARK: - Status Helper
    
    private func updateStatus(_ status: SyncStatus) {
        syncStatus = status
        statusResetTask?.cancel()
        
        if status != .syncing && status != .idle {
            statusResetTask = Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
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
            handleError(error, contextKey: "sync.error_context.send")
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
            handleError(error, contextKey: "sync.error_context.send_image")
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
                print("[send] single item in batch failed: \(error)")
            }
        }
        
        if failureCount > 0 {
            errorMessage = String(format: String(localized: "sync.batch_send_partial_failure", bundle: .main), failureCount)
        }
        
        lastRefreshDate = Date()
        isSending = false
    }

    // MARK: - Clear

    func clearMessage(_ id: String) async {
        do {
            try await api.clearMessage(id: id)
            if let index = messages.firstIndex(where: { $0.id == id }) {
                var updated = messages[index]
                updated.isCleared = true
                updated.updatedAt = Date().ISO8601Format()
                messages[index] = updated
                objectWillChange.send()
            }
            unclearedCount = messages.filter { !$0.isCleared }.count
        } catch {
            handleError(error, contextKey: "sync.error_context.clear")
        }
    }

    func deleteMessage(_ id: String) async {
        do {
            try await api.deleteMessage(id: id)
            messages.removeAll { $0.id == id }
            unclearedCount = messages.filter { !$0.isCleared }.count
        } catch {
            handleError(error, contextKey: "sync.error_context.delete")
        }
    }

    func clearAll() async {
        do {
            _ = try await api.deleteCompletedMessages()
            messages.removeAll { $0.isCleared }
        } catch {
            handleError(error, contextKey: "sync.error_context.delete")
        }
    }

    // MARK: - Helpers

    func reset() {
        stopPolling()
        messages = []
        unclearedCount = 0
        hasCompletedInitialLoad = false
        lastSyncTimestamp = nil
        sessionExpired = false
        syncStatus = .idle
        lastRefreshDate = nil
        resumeRefreshWaiters()
    }

    private func waitForCurrentSyncIfNeeded() async {
        guard isSyncingInternal else { return }

        await withCheckedContinuation { continuation in
            refreshWaiters.append(continuation)
        }
    }

    private func resumeRefreshWaiters() {
        let waiters = refreshWaiters
        refreshWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func handleError(_ error: Error, contextKey: String, silent: Bool = false) {
        let context = String(localized: String.LocalizationValue(contextKey), bundle: .main)
        if isCancellationError(error) {
            print("[SyncManager] CANCELLED in \(context): \(error)")
            Task { @MainActor in
                await SyncDebugLogger.shared.log("\(context) cancelled and ignored")
            }
            return
        }

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
        
        let fullErrorMsg = String(
            format: String(localized: "sync.error_format", bundle: .main),
            context,
            errorDescription,
            errorCode,
            domain
        )
        
        if !silent {
            errorMessage = fullErrorMsg
        }
        
        print("[SyncManager] ERROR in \(context): \(fullErrorMsg)")
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("[SyncManager] Underlying error: \(underlyingError)")
        }
    }

    private func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
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
