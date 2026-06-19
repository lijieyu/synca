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

    @Published var messages: [SyncaMessage] = []
    @Published var categories: [SyncaMessageCategory] = []
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
        messages.filter { $0.type == .image && !$0.isDeleted }
    }

    var orderedMessages: [SyncaMessage] {
        messages.sorted { m1, m2 in
            if m1.isCleared != m2.isCleared {
                return m1.isCleared
            }
            return m1.createdAt < m2.createdAt
        }
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

    func restoreCachedDataIfAvailable() {
        guard api.isAuthenticated else { return }
        
        if let cachedCategories = loadCachedCategories(), !cachedCategories.isEmpty {
            categories = cachedCategories
        }
        
        guard messages.isEmpty else { return }
        guard let cachedMessages = loadCachedMessages(), !cachedMessages.isEmpty else { return }

        messages = cachedMessages
        unclearedCount = cachedMessages.filter { !$0.isCleared }.count
        lastSyncTimestamp = cachedMessages.compactMap(\.updatedAt).max()
        hasCompletedInitialLoad = true
        restoreLocalCategorySelections()
    }

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
            let allCategories = try await api.listMessageCategories()
            messages = allMessages
            categories = allCategories
            unclearedCount = allMessages.filter { !$0.isCleared }.count
            lastSyncTimestamp = allMessages.compactMap(\.updatedAt).max()
            lastRefreshDate = Date()
            persistMessages()
            persistCategories()
            normalizeCategorySelections()
            let appendedRemotely = hasCompletedInitialLoad && allMessages.contains { !existingIDs.contains($0.id) && !$0.isDeleted }
            await AccessManager.shared.refresh()
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
            let allCategories = try await api.listMessageCategories()
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
                persistMessages()
            }
            categories = allCategories
            persistCategories()
            normalizeCategorySelections()
            unclearedCount = messages.filter { !$0.isCleared }.count
            await AccessManager.shared.refresh()
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

    private var hasSyncedTimezone = false

    func startPolling() {
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

    // MARK: - Send Messages

    func sendText(_ text: String, categoryId: String? = nil) async -> SendResult {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return .failed }
        guard trimmedText.count <= 2000 else {
            updateStatus(.error(String(format: String(localized: "message_list.error_too_long", bundle: .main), 2000)))
            return .failed
        }
        isSending = true

        do {
            let message = try await api.sendTextMessage(
                text: trimmedText,
                sourceDevice: currentDeviceName(),
                categoryId: resolvedSendCategoryId(explicitCategoryId: categoryId)
            )
            messages.append(message)
            unclearedCount += 1
            lastSyncTimestamp = message.updatedAt
            lastRefreshDate = Date()
            persistMessages()
            await AccessManager.shared.refresh()
            isSending = false
            return .sent
        } catch APIError.dailyLimitReached(let status) {
            AccessManager.shared.presentUpgrade(using: status)
            isSending = false
            return .blocked
        } catch APIError.messageTooLong(let limit) {
            updateStatus(.error(String(format: String(localized: "message_list.error_too_long", bundle: .main), limit)))
            isSending = false
            return .failed
        } catch {
            handleError(error, contextKey: "sync.error_context.send")
            isSending = false
            return .failed
        }
    }

    func sendImage(_ imageData: Data, categoryId: String? = nil) async {
        isSending = true

        do {
            let message = try await api.sendImageMessage(
                imageData: imageData,
                sourceDevice: currentDeviceName(),
                categoryId: resolvedSendCategoryId(explicitCategoryId: categoryId)
            )
            messages.append(message)
            unclearedCount += 1
            lastSyncTimestamp = message.updatedAt
            lastRefreshDate = Date()
            persistMessages()
            await AccessManager.shared.refresh()
        } catch APIError.dailyLimitReached(let status) {
            AccessManager.shared.presentUpgrade(using: status)
        } catch {
            handleError(error, contextKey: "sync.error_context.send_image")
        }

        isSending = false
    }

    func sendFile(data: Data, fileName: String, mimeType: String? = nil, categoryId: String? = nil) async {
        guard data.count <= PendingFileUpload.maxFileSize else {
            errorMessage = String(localized: "message_file.error_too_large", bundle: .main)
            return
        }

        guard PendingFileUpload.supportedExtensions.contains(URL(fileURLWithPath: fileName).pathExtension.lowercased()) else {
            errorMessage = String(localized: "message_file.error_unsupported", bundle: .main)
            return
        }

        isSending = true

        do {
            let message = try await api.sendFileMessage(
                fileData: data,
                fileName: fileName,
                mimeType: mimeType,
                sourceDevice: currentDeviceName(),
                categoryId: resolvedSendCategoryId(explicitCategoryId: categoryId)
            )
            messages.append(message)
            unclearedCount += 1
            lastSyncTimestamp = message.updatedAt
            lastRefreshDate = Date()
            persistMessages()
            await AccessManager.shared.refresh()
        } catch APIError.dailyLimitReached(let status) {
            AccessManager.shared.presentUpgrade(using: status)
        } catch {
            handleError(error, contextKey: "sync.error_context.send_file")
        }

        isSending = false
    }

    func sendImages(_ imageDatas: [Data], categoryId: String? = nil) async {
        isSending = true
        var failureCount = 0
        var sentCount = 0
        
        for imageData in imageDatas {
            do {
                let message = try await api.sendImageMessage(
                    imageData: imageData,
                    sourceDevice: currentDeviceName(),
                    categoryId: resolvedSendCategoryId(explicitCategoryId: categoryId)
                )
                messages.append(message)
                unclearedCount += 1
                lastSyncTimestamp = message.updatedAt
                sentCount += 1
                persistMessages()
            } catch APIError.dailyLimitReached(let status) {
                AccessManager.shared.presentUpgrade(using: status)
                break
            } catch {
                failureCount += 1
                print("[send] single item in batch failed: \(error)")
            }
        }
        
        if failureCount > 0 {
            errorMessage = String(format: String(localized: "sync.batch_send_partial_failure", bundle: .main), failureCount)
        }
        
        lastRefreshDate = Date()
        if sentCount > 0 {
            await AccessManager.shared.refresh()
        }
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
                persistMessages()
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
            persistMessages()
        } catch {
            handleError(error, contextKey: "sync.error_context.delete")
        }
    }

    func updateMessageCategory(_ messageId: String, categoryId: String?) async {
        do {
            let updated = try await api.updateMessageCategoryAssignment(messageId: messageId, categoryId: categoryId)
            if let index = messages.firstIndex(where: { $0.id == messageId }) {
                messages[index] = updated
                persistMessages()
            }
        } catch {
            handleError(error, contextKey: "sync.error_context.send")
        }
    }

    func createCategory(name: String, color: MessageCategoryColor) async -> SyncaMessageCategory? {
        do {
            let category = try await api.createMessageCategory(name: name, color: color)
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
            handleError(error, contextKey: "sync.error_context.send")
            return nil
        }
    }

    func updateCategory(id: String, name: String? = nil, color: MessageCategoryColor? = nil) async {
        do {
            let updated = try await api.updateMessageCategory(id: id, name: name, color: color)
            if let index = categories.firstIndex(where: { $0.id == id }) {
                categories[index] = updated
                persistCategories()
            }
        } catch {
            handleError(error, contextKey: "sync.error_context.send")
        }
    }

    func reorderCategories(ids: [String]) async {
        do {
            try await api.reorderMessageCategories(categoryIds: ids)
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
            handleError(error, contextKey: "sync.error_context.send")
        }
    }

    func deleteCategory(id: String) async {
        do {
            try await api.deleteMessageCategory(id: id)
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
            handleError(error, contextKey: "sync.error_context.delete")
        }
    }

    func clearCompleted(categoryId: String? = nil) async {
        do {
            _ = try await api.deleteCompletedMessages(categoryId: categoryId)
            messages.removeAll { message in
                guard message.isCleared else { return false }
                guard let categoryId else { return true }
                return message.categoryId == categoryId
            }
            unclearedCount = messages.filter { !$0.isCleared }.count
            persistMessages()
        } catch {
            handleError(error, contextKey: "sync.error_context.delete")
        }
    }

    func clearCurrentList(categoryId: String? = nil) async {
        do {
            _ = try await api.clearAllMessages(categoryId: categoryId)
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
            handleError(error, contextKey: "sync.error_context.clear")
        }
    }

    // MARK: - Helpers

    func reset() {
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
        DeviceInfo.displayModelName
    }

    func messages(for categoryId: String?) -> [SyncaMessage] {
        let base = orderedMessages
        guard let categoryId, categoryId != allCategoryPseudoId else { return base }
        return base.filter { $0.categoryId == categoryId }
    }

    func selectCategory(_ categoryId: String?) {
        selectedCategoryId = categoryId ?? defaultCategory?.id ?? allCategoryPseudoId
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
            ?? defaultCategory?.id
    }

    private func normalizeCategorySelections() {
        if categories.isEmpty {
            selectedCategoryId = allCategoryPseudoId
            selectedCategoryIDsForTiledLayout = []
            return
        }

        let validIds = Set(categories.map(\.id))
        if let selectedCategoryId, selectedCategoryId != allCategoryPseudoId, !validIds.contains(selectedCategoryId) {
            self.selectedCategoryId = defaultCategory?.id ?? allCategoryPseudoId
        } else if self.selectedCategoryId == nil {
            restoreLocalCategorySelections()
            if self.selectedCategoryId == nil {
                self.selectedCategoryId = defaultCategory?.id ?? allCategoryPseudoId
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
        guard api.isAuthenticated else { return }
        guard let cacheURL = messagesCacheURL() else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(messages)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("[SyncManager] Failed to persist messages cache: \(error)")
        }
    }

    private func loadCachedMessages() -> [SyncaMessage]? {
        guard let cacheURL = messagesCacheURL(),
              FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            return try decoder.decode([SyncaMessage].self, from: data)
        } catch {
            print("[SyncManager] Failed to load messages cache: \(error)")
            return nil
        }
    }

    private func removeCachedMessages() {
        guard let cacheURL = messagesCacheURL(),
              FileManager.default.fileExists(atPath: cacheURL.path) else {
            return
        }

        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func messagesCacheURL() -> URL? {
        guard let userID = api.currentUserId, !userID.isEmpty else { return nil }
        return cacheDirectoryURL.appendingPathComponent("messages-\(userID).json")
    }

    private func persistCategories() {
        guard api.isAuthenticated else { return }
        guard let cacheURL = categoriesCacheURL() else { return }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(categories)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            print("[SyncManager] Failed to persist categories cache: \(error)")
        }
    }

    private func loadCachedCategories() -> [SyncaMessageCategory]? {
        guard let cacheURL = categoriesCacheURL(),
              FileManager.default.fileExists(atPath: cacheURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheURL)
            let decoder = JSONDecoder()
            return try decoder.decode([SyncaMessageCategory].self, from: data)
        } catch {
            print("[SyncManager] Failed to load categories cache: \(error)")
            return nil
        }
    }

    private func removeCachedCategories() {
        guard let cacheURL = categoriesCacheURL(),
              FileManager.default.fileExists(atPath: cacheURL.path) else {
            return
        }
        try? FileManager.default.removeItem(at: cacheURL)
    }

    private func categoriesCacheURL() -> URL? {
        guard let userID = api.currentUserId, !userID.isEmpty else { return nil }
        return cacheDirectoryURL.appendingPathComponent("categories-\(userID).json")
    }
}
