import Foundation
import Combine
#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class SyncManager: ObservableObject {
    static let shared = SyncManager()

    enum SendResult {
        case sent
        case blocked
        case failed
    }

    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success
        case progress(String)
        case successMessage(String)
        case error(String)
        
        var isSyncing: Bool { self == .syncing }
    }

    @Published var messages: [SyncaMessage] = [] {
        didSet { cachedMessageIndex = nil; syncState.changed() }
    }
    private var cachedMessageIndex: MessageListIndex?

    private var messageIndex: MessageListIndex {
        if let cachedMessageIndex { return cachedMessageIndex }
        let index = MessageListIndex(messages: messages)
        cachedMessageIndex = index
        return index
    }
    @Published var categories: [SyncaMessageCategory] = [] {
        didSet { syncState.changed() }
    }
    private var syncState = MessageSyncState()
    private let snapshotStore = MessageSnapshotStore()
    private var storageRevision: UInt64 = 0
    private var messageWriteTask: Task<Void, Never>?
    private var categoryWriteTask: Task<Void, Never>?
    private var activeSendCount = 0

    private func beginSending() -> UUID {
        activeSendCount += 1
        isSending = true
        return syncState.generation
    }

    private func endSending(_ generation: UUID) {
        guard generation == syncState.generation else { return }
        activeSendCount = max(0, activeSendCount - 1)
        isSending = activeSendCount > 0
    }
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
    @Published var selectedCategoryId: String? = nil
    @Published var selectedCategoryIDsForTiledLayout: [String] = []

    var imageMessages: [SyncaMessage] {
        messages.filter { $0.type == .image && !$0.isDeleted && !$0.isAttachmentExpired }
    }

    var orderedMessages: [SyncaMessage] { messageIndex.ordered }

    func todoCount(for categoryId: String? = nil) -> Int {
        guard let categoryId, categoryId != allCategoryPseudoId else { return messageIndex.todoCount }
        return messageIndex.todoCountsByCategory[categoryId, default: 0]
    }

    var allCategoryPseudoId: String { "__all__" }

    var defaultCategory: SyncaMessageCategory? {
        categories.first(where: \.isDefault)
    }

    private var pollTimer: Timer?
    private var lastSyncTimestamp: String?
    private let api = APIClient.shared
    private var statusResetTask: Task<Void, Never>?
    private var feedbackOperationID = UUID()
    private var isSyncingInternal = false // Concurrency lock
    private var refreshWaiters: [CheckedContinuation<Void, Never>] = []
    private var pollCycleCount = 0
    private let cacheDirectoryURL: URL = {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directoryURL = baseURL.appendingPathComponent("Synca", isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }()

    private init() {}

    func restoreCachedDataIfAvailable() async {
        guard api.isAuthenticated, messages.isEmpty,
              let messagesURL = messagesCacheURL(), let categoriesURL = categoriesCacheURL() else { return }
        let ticket = syncState.ticket
        let cachedCategories = await snapshotStore.read([SyncaMessageCategory].self, from: categoriesURL)
        let cachedMessages = await snapshotStore.read([SyncaMessage].self, from: messagesURL)
        guard syncState.accepts(ticket), api.isAuthenticated else { return }
        if let cachedCategories { categories = cachedCategories }
        if let cachedMessages, !cachedMessages.isEmpty {
            messages = cachedMessages
            unclearedCount = cachedMessages.filter { !$0.isCleared }.count
            // A cache contains visible messages, not the complete change stream (including deletions).
            lastSyncTimestamp = nil
            hasCompletedInitialLoad = true
        }
        restoreLocalCategorySelections()
    }

    // MARK: - Full Sync

    func fullSync(manual: Bool = false, showSuccessStatus: Bool = true) async {
        guard api.isAuthenticated else { return }
        guard !isSyncingInternal else { return }
        
        let ticket = syncState.ticket
        isSyncingInternal = true
        isLoading = messages.isEmpty && manual
        errorMessage = nil
        
        defer {
            if ticket.generation == syncState.generation {
                isLoading = false
                hasCompletedInitialLoad = true
                isSyncingInternal = false
                resumeRefreshWaiters()
            }
        }
        
        if manual { updateStatus(.syncing) }

        do {
            let existingIDs = Set(messages.map(\.id))
            let allMessages = try await api.listMessages()
            let allCategories = try await api.listMessageCategories()
            guard syncState.accepts(ticket) else {
                if ticket.generation == syncState.generation && manual { updateStatus(.idle) }
                return
            }
            if messages != allMessages { messages = allMessages; persistMessages() }
            if categories != allCategories { categories = allCategories; persistCategories() }
            unclearedCount = allMessages.filter { !$0.isCleared }.count
            lastSyncTimestamp = allMessages.compactMap(\.updatedAt).max()
            lastRefreshDate = Date()
            normalizeCategorySelections()
            let appendedRemotely = hasCompletedInitialLoad && allMessages.contains { !existingIDs.contains($0.id) && !$0.isDeleted }
            await AccessManager.shared.refresh()
            guard ticket.generation == syncState.generation else { return }
            if appendedRemotely {
                remoteAppendEvent = UUID()
            }
            if manual && showSuccessStatus { updateStatus(.success) }
        } catch {
            guard ticket.generation == syncState.generation else { return }
            if isCancellationError(error) { return }
            handleError(error, contextKey: "sync.error_context.sync")
            if manual { updateStatus(.error(error.localizedDescription)) }
        }
    }

    // MARK: - Incremental Sync

    func incrementalSync(manual: Bool = false) async {
        guard api.isAuthenticated else { return }
        guard !isSyncingInternal else { return }
        
        let ticket = syncState.ticket
        isSyncingInternal = true
        defer {
            if ticket.generation == syncState.generation {
                isSyncingInternal = false
                resumeRefreshWaiters()
            }
        }
        
        if manual { updateStatus(.syncing) }

        do {
            let since = lastSyncTimestamp
            let newMessages = try await api.listMessages(since: since)
            let allCategories = try await api.listMessageCategories()
            guard syncState.accepts(ticket) else {
                if ticket.generation == syncState.generation && manual { updateStatus(.idle) }
                return
            }
            var appendedRemotely = false

            if !newMessages.isEmpty {
                let existingIDs = Set(messages.map(\.id))
                let merged = MessageSyncState.merging(newMessages, into: messages)
                appendedRemotely = newMessages.contains { !$0.isDeleted && !existingIDs.contains($0.id) }
                if merged != messages { messages = merged; persistMessages() }
                // Advance from the response, including tombstones, never from locally edited rows.
                lastSyncTimestamp = ([lastSyncTimestamp].compactMap { $0 } + newMessages.map(\.updatedAt)).max()
                lastRefreshDate = Date()
            }
            if categories != allCategories { categories = allCategories; persistCategories() }
            normalizeCategorySelections()
            unclearedCount = messages.filter { !$0.isCleared }.count
            await AccessManager.shared.refresh()
            guard ticket.generation == syncState.generation else { return }
            if appendedRemotely && hasCompletedInitialLoad {
                remoteAppendEvent = UUID()
            }
            if manual { updateStatus(.success) }
        } catch {
            guard ticket.generation == syncState.generation else { return }
            if isCancellationError(error) { return }
            handleError(error, contextKey: "sync.error_context.sync", silent: !manual)
            if manual { updateStatus(.error(error.localizedDescription)) }
        }
    }

    // MARK: - Pull to Refresh

    func refresh() async {
        let generation = syncState.generation
        await waitForCurrentSyncIfNeeded()
        guard generation == syncState.generation, api.isAuthenticated else { return }
        isRefreshing = true
        stopPolling()
        await fullSync(manual: true)
        guard generation == syncState.generation, api.isAuthenticated else { return }
        startPolling()
        isRefreshing = false
    }

    // MARK: - Polling

    private var hasSyncedTimezone = false

    func startPolling() {
        guard api.isAuthenticated else { return }
        stopPolling()
        pollCycleCount = 0
        
        if !hasSyncedTimezone {
            hasSyncedTimezone = true
            Task {
                try? await api.updateTimezone(offsetSeconds: TimeZone.current.secondsFromGMT())
            }
        }
        
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

    @discardableResult
    func beginProgressFeedback(_ message: String) -> UUID {
        feedbackOperationID = UUID()
        updateStatus(.progress(message))
        return feedbackOperationID
    }

    func showSuccessFeedback(_ message: String, for operationID: UUID? = nil) {
        guard operationID == nil || operationID == feedbackOperationID else { return }
        if operationID == nil { feedbackOperationID = UUID() }
        updateStatus(.successMessage(message))
    }

    func showErrorFeedback(_ message: String, for operationID: UUID? = nil) {
        guard operationID == nil || operationID == feedbackOperationID else { return }
        if operationID == nil { feedbackOperationID = UUID() }
        updateStatus(.error(message))
    }
    
    private func updateStatus(_ status: SyncStatus) {
        switch status {
        case .progress, .successMessage:
            break
        default:
            feedbackOperationID = UUID()
        }
        syncStatus = status
        statusResetTask?.cancel()
        
        if status != .syncing && status != .idle,
           !isProgressStatus(status) {
            statusResetTask = Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if !Task.isCancelled {
                    syncStatus = .idle
                }
            }
        }
    }

    private func isProgressStatus(_ status: SyncStatus) -> Bool {
        if case .progress = status { return true }
        return false
    }

    @Published var uploadProgress: Double?
    @Published var failedFile: PendingFileUpload?
    private var failedFileCategory: String?
    private var fileUploadTask: Task<SyncaMessage, Error>?
    func cancelFileUpload() { fileUploadTask?.cancel(); api.cancelUploads() }
    func retryFileUpload() async {
        guard let file = failedFile, !isSending else { return }
        await sendFile(file: file, categoryId: failedFileCategory)
    }

    // MARK: - Send Messages

    func sendText(_ text: String, categoryId: String? = nil) async -> SendResult {
        let operationGeneration = syncState.generation
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return .failed }
        guard trimmedText.count <= 2000 else {
            updateStatus(.error(String(format: String(localized: "message_list.error_too_long", bundle: .main), 2000)))
            return .failed
        }
        let sendGeneration = beginSending()
        defer { endSending(sendGeneration) }

        do {
            let message = try await api.sendTextMessage(
                text: trimmedText,
                sourceDevice: currentDeviceName(),
                categoryId: resolvedSendCategoryId(explicitCategoryId: categoryId)
            )
            guard operationGeneration == syncState.generation else { return .failed }
            messages.append(message)
            unclearedCount += 1
            lastRefreshDate = Date()
            persistMessages()
            await AccessManager.shared.refresh()
            return .sent
        } catch APIError.dailyLimitReached(let status) {
            guard operationGeneration == syncState.generation else { return .failed }
            AccessManager.shared.presentUpgrade(using: status)
            return .blocked
        } catch APIError.messageTooLong(let limit) {
            guard operationGeneration == syncState.generation else { return .failed }
            updateStatus(.error(String(format: String(localized: "message_list.error_too_long", bundle: .main), limit)))
            return .failed
        } catch {
            guard operationGeneration == syncState.generation else { return .failed }
            handleError(error, contextKey: "sync.error_context.send")
            return .failed
        }
    }

    func sendImage(_ imageData: Data, categoryId: String? = nil) async {
        let operationGeneration = syncState.generation
        errorMessage = nil
        let sendGeneration = beginSending()
        defer { endSending(sendGeneration) }

        do {
            let message = try await api.sendImageMessage(
                imageData: imageData,
                sourceDevice: currentDeviceName(),
                categoryId: resolvedSendCategoryId(explicitCategoryId: categoryId)
            )
            guard operationGeneration == syncState.generation else { return }
            messages.append(message)
            unclearedCount += 1
            lastRefreshDate = Date()
            persistMessages()
            await AccessManager.shared.refresh()
        } catch APIError.dailyLimitReached(let status) {
            guard operationGeneration == syncState.generation else { return }
            AccessManager.shared.presentUpgrade(using: status)
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.send_image")
        }

    }

    func sendFile(file: PendingFileUpload, categoryId: String? = nil) async {
        guard !isSending else { return }
        let operationGeneration = syncState.generation
        guard file.fileSize <= PendingFileUpload.maxFileSize else {
            errorMessage = String(localized: "message_file.error_too_large", bundle: .main)
            return
        }

        guard PendingFileUpload.supportedExtensions.contains(URL(fileURLWithPath: file.fileName).pathExtension.lowercased()) else {
            errorMessage = String(localized: "message_file.error_unsupported", bundle: .main)
            return
        }

        let sendGeneration = beginSending()
        defer { endSending(sendGeneration); if operationGeneration == syncState.generation { uploadProgress = nil } }
        await AccessManager.shared.refresh()
        guard operationGeneration == syncState.generation else { return }
        if let status = AccessManager.shared.status, !(status.storage?.canUploadFiles ?? (!status.isTrial && status.isUnlimited)) {
            failedFile = file
            failedFileCategory = categoryId
            AccessManager.shared.presentUpgrade(using: nil)
            return
        }
        failedFile = nil
        uploadProgress = 0

        do {
            let task = Task { try await api.sendFileMessage(
                file: file,
                sourceDevice: currentDeviceName(),
                categoryId: resolvedSendCategoryId(explicitCategoryId: categoryId),
                progress: { value in Task { @MainActor in
                    guard operationGeneration == self.syncState.generation, self.uploadProgress != nil else { return }
                    self.uploadProgress = value
                } }
            ) }
            fileUploadTask = task
            defer { fileUploadTask = nil }
            let message = try await task.value
            guard operationGeneration == syncState.generation else { return }
            if !messages.contains(where: { $0.id == message.id }) { messages.append(message) }
            unclearedCount = messages.filter { !$0.isCleared }.count
            lastRefreshDate = Date()
            persistMessages()
            await AccessManager.shared.refresh()
        } catch APIError.dailyLimitReached(let status) {
            guard operationGeneration == syncState.generation else { return }
            AccessManager.shared.presentUpgrade(using: status)
        } catch {
            guard operationGeneration == syncState.generation else { return }
            failedFile = file
            failedFileCategory = categoryId
            if case APIError.fileRequiresPaid = error { AccessManager.shared.presentUpgrade(using: nil) }
            handleError(error, contextKey: "sync.error_context.send_file")
        }

    }

    func sendImages(_ imageDatas: [Data], categoryId: String? = nil) async {
        let operationGeneration = syncState.generation
        guard !imageDatas.isEmpty else { return }
        if imageDatas.count == 1 {
            await sendImage(imageDatas[0], categoryId: categoryId)
            return
        }

        errorMessage = nil
        let sendGeneration = beginSending()
        defer { endSending(sendGeneration) }
        let targetCategoryId = resolvedSendCategoryId(explicitCategoryId: categoryId)
        var sentCount = 0
        var firstError: Error?
        var wasBlocked = false

        for imageData in imageDatas {
            guard sendGeneration == syncState.generation else { return }
            do {
                try Task.checkCancellation()
                let message = try await api.sendImageMessage(
                    imageData: imageData,
                    sourceDevice: currentDeviceName(),
                    categoryId: targetCategoryId
                )
                guard operationGeneration == syncState.generation else { return }
                messages.append(message)
                unclearedCount += 1
                sentCount += 1
                persistMessages()
            } catch APIError.dailyLimitReached(let status) {
                guard operationGeneration == syncState.generation else { return }
                AccessManager.shared.presentUpgrade(using: status)
                wasBlocked = true
                break
            } catch APIError.unauthorized {
                guard operationGeneration == syncState.generation else { return }
                handleError(APIError.unauthorized, contextKey: "sync.error_context.send_image")
                return
            } catch {
                guard operationGeneration == syncState.generation else { return }
                if isCancellationError(error) { return }
                if firstError == nil { firstError = error }
            }
        }

        if sentCount > 0 { lastRefreshDate = Date() }
        if let firstError {
            let key = sentCount == 0 ? "sync.images_send_failed" : "sync.batch_send_partial_failure"
            let format = String(localized: String.LocalizationValue(key), bundle: .main)
            errorMessage = sentCount == 0
                ? String(format: format, firstError.localizedDescription)
                : String(format: format, sentCount, imageDatas.count - sentCount, firstError.localizedDescription)
        } else if wasBlocked && sentCount > 0 {
            errorMessage = String(format: String(localized: "sync.images_send_limit", bundle: .main), sentCount, imageDatas.count - sentCount)
        }
        if sentCount > 0 { await AccessManager.shared.refresh() }
    }

    // MARK: - Clear

    func clearMessage(_ id: String) async {
        let operationGeneration = syncState.generation
        do {
            try await api.clearMessage(id: id)
            guard operationGeneration == syncState.generation else { return }
            if let index = messages.firstIndex(where: { $0.id == id }) {
                var updated = messages[index]
                updated.isCleared = true
                updated.updatedAt = Date().ISO8601Format()
                messages[index] = updated
                objectWillChange.send()
                persistMessages()
            }
            unclearedCount = messages.filter { !$0.isCleared }.count
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.clear")
        }
    }

    func deleteMessage(_ id: String) async {
        let operationGeneration = syncState.generation
        do {
            try await api.deleteMessage(id: id)
            guard operationGeneration == syncState.generation else { return }
            messages.removeAll { $0.id == id }
            unclearedCount = messages.filter { !$0.isCleared }.count
            persistMessages()
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.delete")
        }
    }

    func updateMessageCategory(_ messageId: String, categoryId: String?) async {
        let operationGeneration = syncState.generation
        do {
            let updated = try await api.updateMessageCategoryAssignment(messageId: messageId, categoryId: categoryId)
            guard operationGeneration == syncState.generation else { return }
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index] = updated
                persistMessages()
            }
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.send")
        }
    }

    func createCategory(name: String, color: MessageCategoryColor) async -> SyncaMessageCategory? {
        let operationGeneration = syncState.generation
        do {
            let category = try await api.createMessageCategory(name: name, color: color)
            guard operationGeneration == syncState.generation else { return nil }
            categories.append(category)
            categories.sort { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
            persistCategories()
            normalizeCategorySelections()
            return category
        } catch {
            guard operationGeneration == syncState.generation else { return nil }
            handleError(error, contextKey: "sync.error_context.send")
            return nil
        }
    }

    func updateCategory(id: String, name: String? = nil, color: MessageCategoryColor? = nil) async {
        let operationGeneration = syncState.generation
        do {
            let updated = try await api.updateMessageCategory(id: id, name: name, color: color)
            guard operationGeneration == syncState.generation else { return }
            if let index = categories.firstIndex(where: { $0.id == id }) {
                categories[index] = updated
                persistCategories()
            }
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.send")
        }
    }

    func reorderCategories(ids: [String]) async {
        let operationGeneration = syncState.generation
        do {
            try await api.reorderMessageCategories(categoryIds: ids)
            guard operationGeneration == syncState.generation else { return }
            let orderById = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, ($0.offset + 1) * 1000) })
            for index in categories.indices {
                if let sortOrder = orderById[categories[index].id] {
                    categories[index].sortOrder = sortOrder
                }
            }
            categories.sort { lhs, rhs in
                if lhs.isDefault != rhs.isDefault { return lhs.isDefault }
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.createdAt < rhs.createdAt
            }
            persistCategories()
            normalizeCategorySelections()
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.send")
        }
    }

    func deleteCategory(id: String) async {
        let operationGeneration = syncState.generation
        do {
            try await api.deleteMessageCategory(id: id)
            guard operationGeneration == syncState.generation else { return }
            categories.removeAll { $0.id == id }
            if let defaultCategory {
                for index in messages.indices where messages[index].categoryId == id {
                    messages[index].categoryId = defaultCategory.id
                    messages[index].categoryName = defaultCategory.name
                    messages[index].categoryColor = defaultCategory.color
                    messages[index].categoryIsDefault = true
                }
            }
            persistCategories()
            normalizeCategorySelections()
            persistMessages()
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.delete")
        }
    }

    func clearCompleted(categoryId: String? = nil) async {
        let operationGeneration = syncState.generation
        do {
            _ = try await api.deleteCompletedMessages(categoryId: categoryId)
            guard operationGeneration == syncState.generation else { return }
            messages.removeAll { message in
                guard message.isCleared else { return false }
                guard let categoryId else { return true }
                return message.categoryId == categoryId
            }
            unclearedCount = messages.filter { !$0.isCleared }.count
            persistMessages()
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.delete")
        }
    }

    func clearCurrentList(categoryId: String? = nil) async {
        let operationGeneration = syncState.generation
        do {
            _ = try await api.clearAllMessages(categoryId: categoryId)
            guard operationGeneration == syncState.generation else { return }
            for index in messages.indices {
                guard !messages[index].isCleared else { continue }
                if let categoryId, messages[index].categoryId != categoryId {
                    continue
                }
                messages[index].isCleared = true
                messages[index].updatedAt = Date().ISO8601Format()
            }
            unclearedCount = messages.filter { !$0.isCleared }.count
            persistMessages()
        } catch {
            guard operationGeneration == syncState.generation else { return }
            handleError(error, contextKey: "sync.error_context.clear")
        }
    }

    // MARK: - Helpers

    func reset() {
        fileUploadTask?.cancel()
        failedFile = nil
        uploadProgress = nil
        syncState.reset()
        api.cancelPendingRequests()
        messageWriteTask?.cancel()
        categoryWriteTask?.cancel()
        statusResetTask?.cancel()
        isSyncingInternal = false
        isRefreshing = false
        isLoading = false
        activeSendCount = 0
        isSending = false
        hasSyncedTimezone = false
        errorMessage = nil
        stopPolling()
        messages = []
        unclearedCount = 0
        hasCompletedInitialLoad = false
        categories = []
        selectedCategoryId = nil
        selectedCategoryIDsForTiledLayout = []
        lastSyncTimestamp = nil
        sessionExpired = false
        syncStatus = .idle
        lastRefreshDate = nil
        removeCachedMessages()
        removeCachedCategories()
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
                SyncDebugLogger.shared.log("\(context) cancelled and ignored")
            }
            return
        }

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
        DeviceInfo.displayModelName
    }

    func messages(for categoryId: String?) -> [SyncaMessage] {
        guard let categoryId, categoryId != allCategoryPseudoId else { return messageIndex.ordered }
        return messageIndex.byCategory[categoryId, default: []]
    }

    func selectCategory(_ categoryId: String?) {
        selectedCategoryId = categoryId ?? allCategoryPseudoId
        SettingsManager.shared.setSelectedMessageCategoryId(selectedCategoryId, for: api.currentUserId)
        normalizeCategorySelections()
    }

    func setDefaultSendCategoryId(_ categoryId: String?) {
        SettingsManager.shared.setDefaultSendCategoryId(categoryId, for: api.currentUserId)
    }

    func defaultSendCategoryId() -> String? {
        let stored = SettingsManager.shared.defaultSendCategoryId(for: api.currentUserId)
        if let stored, categories.contains(where: { $0.id == stored }) {
            return stored
        }
        return defaultCategory?.id
    }

    private func resolvedSendCategoryId(explicitCategoryId: String?) -> String? {
        if let explicitCategoryId, explicitCategoryId != allCategoryPseudoId {
            return explicitCategoryId
        }

        if selectedCategoryId == allCategoryPseudoId {
            return defaultSendCategoryId()
        }

        return selectedCategoryId ?? defaultCategory?.id
    }

    private func restoreLocalCategorySelections() {
        selectedCategoryId = SettingsManager.shared.selectedMessageCategoryId(for: api.currentUserId)
            ?? allCategoryPseudoId
    }

    private func normalizeCategorySelections() {
        if categories.isEmpty {
            selectedCategoryId = allCategoryPseudoId
            selectedCategoryIDsForTiledLayout = []
            return
        }

        let validIds = Set(categories.map(\.id))
        if let selectedCategoryId, selectedCategoryId != allCategoryPseudoId, !validIds.contains(selectedCategoryId) {
            self.selectedCategoryId = allCategoryPseudoId
        } else if self.selectedCategoryId == nil {
            restoreLocalCategorySelections()
            if self.selectedCategoryId == nil {
                self.selectedCategoryId = allCategoryPseudoId
            }
        }

        if let storedDefault = SettingsManager.shared.defaultSendCategoryId(for: api.currentUserId), !validIds.contains(storedDefault) {
            SettingsManager.shared.setDefaultSendCategoryId(defaultCategory?.id, for: api.currentUserId)
        } else if SettingsManager.shared.defaultSendCategoryId(for: api.currentUserId) == nil {
            SettingsManager.shared.setDefaultSendCategoryId(defaultCategory?.id, for: api.currentUserId)
        }

        let nonDefaultCategoryIds = categories.filter { !$0.isDefault }.map(\.id)
        if selectedCategoryIDsForTiledLayout.isEmpty {
            selectedCategoryIDsForTiledLayout = nonDefaultCategoryIds
        } else {
            selectedCategoryIDsForTiledLayout = selectedCategoryIDsForTiledLayout.filter { validIds.contains($0) }
        }
    }

    private func persistMessages() {
        guard api.isAuthenticated, let url = messagesCacheURL() else { return }
        messageWriteTask?.cancel()
        storageRevision &+= 1
        let revision = storageRevision
        let snapshot = messages
        let store = snapshotStore
        messageWriteTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            do { try await store.write(snapshot, to: url, revision: revision) }
            catch { print("[cache] Message write failed: \(error)") }
        }
    }

    private func removeCachedMessages() {
        guard let url = messagesCacheURL() else { return }
        storageRevision &+= 1
        let revision = storageRevision
        Task { try? await snapshotStore.remove(url, revision: revision) }
    }

    private func messagesCacheURL() -> URL? {
        guard let userID = api.currentUserId, !userID.isEmpty else { return nil }
        return cacheDirectoryURL.appendingPathComponent("messages-\(userID).json")
    }

    private func persistCategories() {
        guard api.isAuthenticated, let url = categoriesCacheURL() else { return }
        categoryWriteTask?.cancel()
        storageRevision &+= 1
        let revision = storageRevision
        let snapshot = categories
        let store = snapshotStore
        categoryWriteTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            do { try await store.write(snapshot, to: url, revision: revision) }
            catch { print("[cache] Category write failed: \(error)") }
        }
    }

    private func removeCachedCategories() {
        guard let url = categoriesCacheURL() else { return }
        storageRevision &+= 1
        let revision = storageRevision
        Task { try? await snapshotStore.remove(url, revision: revision) }
    }

    private func categoriesCacheURL() -> URL? {
        guard let userID = api.currentUserId, !userID.isEmpty else { return nil }
        return cacheDirectoryURL.appendingPathComponent("categories-\(userID).json")
    }
}
