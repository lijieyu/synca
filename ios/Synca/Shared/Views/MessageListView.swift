import SwiftUI
import PhotosUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

struct MessageListView: View {
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var accessManager: AccessManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @ObservedObject private var settings = SettingsManager.shared
    @State private var inputText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showLogoutConfirm = false
    @State private var showClearAllConfirm = false
    @State private var showAboutInfo = false
    @State private var showAccountInfo = false
    @State private var showFeedbackComposer = false
    @State private var showSessionExpired = false
    @State private var showDeleteAccountConfirm = false
    @State private var showDeleteAccountSuccess = false
    @State private var deleteAccountErrorMessage: String?
    @State private var inputHeight: CGFloat = 40
    @State private var selectedImageMessage: SyncaMessage? // #NEW: Centralized gallery state
    @State private var shouldScrollToBottomAfterSend = false
    @State private var postSendScrollWindowID = UUID()
    @State private var shouldScrollToBottomAfterInitialLoad = false
    @State private var initialLoadScrollWindowID = UUID()
    @State private var showFeedbackSuccessToast = false
    @State private var showCategoryManager = false

    var body: some View {
        NavigationStack {
            rootContent
            .background(Color.syncaPageBackground.ignoresSafeArea())
            .navigationTitle("")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                titleToolbarItem
                actionToolbarItems
            }
#endif
            .alert("message_list.clear_all_confirm_title", isPresented: $showClearAllConfirm) {
                Button("common.cancel", role: .cancel) {}
                Button("common.delete", role: .destructive) {
                    Task { await handleTopClearAction() }
                }
            } message: {
                Text(clearActionMessage)
            }
            .alert("message_list.logout_confirm_title", isPresented: $showLogoutConfirm) {
                Button("common.cancel", role: .cancel) {}
                Button("message_list.logout", role: .destructive) {
                    syncManager.reset()
                    AuthService.shared.signOut()
                }
            } message: {
                Text("message_list.logout_confirm_message")
            }
            .alert("account.delete_confirm_title", isPresented: $showDeleteAccountConfirm) {
                Button("common.cancel", role: .cancel) {}
                Button("account.delete_action", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("account.delete_confirm_message")
            }
            .alert("account.delete_success_title", isPresented: $showDeleteAccountSuccess) {
                Button("common.ok") {
                    syncManager.reset()
                    AuthService.shared.signOut()
                }
            } message: {
                Text("account.delete_success_message")
            }
            .alert("account.delete_failed_title", isPresented: Binding(
                get: { deleteAccountErrorMessage != nil },
                set: { if !$0 { deleteAccountErrorMessage = nil } }
            )) {
                Button("common.ok", role: .cancel) {
                    deleteAccountErrorMessage = nil
                }
            } message: {
                Text(deleteAccountErrorMessage ?? String(localized: "account.delete_failed_message", bundle: .main))
            }
            .sheet(isPresented: $showAccountInfo) {
                AccountSheet(
                    accountEmail: api.currentUserEmail,
                    onRequestDeleteAccount: {
                        showAccountInfo = false
                        showDeleteAccountConfirm = true
                    },
                    onRequestSignOut: {
                        showAccountInfo = false
                        showLogoutConfirm = true
                    }
                )
            }
            .sheet(isPresented: $showAboutInfo) {
                AboutSyncaSheet()
            }
            .sheet(isPresented: $showCategoryManager) {
                MessageCategoryManagerSheet()
                    .environmentObject(syncManager)
            }
            .alert("message_list.session_expired_title", isPresented: $showSessionExpired) {
                Button("message_list.sign_in_again") {
                    syncManager.reset()
                }
            } message: {
                Text("message_list.session_expired_message")
            }
        }
        .overlay(alignment: .top) { syncStatusOverlay }
        .overlay(alignment: .top) { feedbackToastOverlay }
        .overlay { loadingOverlay }
        .sheet(isPresented: $accessManager.showAccessCenter) {
            AccessCenterView()
                .environmentObject(accessManager)
                .environmentObject(purchaseManager)
        }
        .sheet(isPresented: $showFeedbackComposer) {
            FeedbackComposerView()
                .environmentObject(api)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: supportedDocumentTypes,
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImportedFiles(result) }
        }
        .imagePreviewSheet(item: $selectedImageMessage, syncManager: syncManager)
        .task {
            shouldScrollToBottomAfterInitialLoad = true
            syncManager.restoreCachedMessagesIfAvailable()
            await PushTokenManager.shared.uploadCachedTokenIfPossible()
            await purchaseManager.loadProducts()
            _ = try? await purchaseManager.syncLatestTransactions()
            await syncManager.fullSync(manual: true, showSuccessStatus: false)
            if !syncManager.orderedMessages.isEmpty {
                beginInitialLoadScrollWindow()
            }
            syncManager.startPolling()
            self.updateBadge()
        }
        .onChange(of: syncManager.unclearedCount) { _ in
            self.updateBadge()
        }
        .onChange(of: syncManager.sessionExpired) { expired in
            if expired {
                showSessionExpired = true
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await syncManager.fullSync(manual: false, showSuccessStatus: false) }
        }
        #elseif os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await syncManager.fullSync(manual: false, showSuccessStatus: false) }
        }
        #endif
        .onDisappear {
            syncManager.stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncaFeedbackSubmitted)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showFeedbackSuccessToast = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showFeedbackSuccessToast = false
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncaRequestClearAll)) { _ in
            showClearAllConfirm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncaRequestAccount)) { _ in
            showAccountInfo = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncaRequestCategoryManager)) { _ in
            showCategoryManager = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncaRequestFeedbackComposer)) { _ in
            showFeedbackComposer = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncaRequestAbout)) { _ in
            showAboutInfo = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncaRequestSignOut)) { _ in
            showLogoutConfirm = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .syncaRequestAbout)) { _ in
            showAboutInfo = true
        }
    }

    private var rootContent: some View {
        VStack(spacing: 0) {
            if !isTiledLayout {
                categoryToolbar
            }
            if isTiledLayout {
                tiledBoardView
            } else {
                VStack(spacing: 0) {
                    messageList
                    Divider()
                    inputBar
                }
            }
        }
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var actionToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            refreshButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            clearAllButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            settingsMenu
        }
    }

    @ToolbarContentBuilder
    private var titleToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Text("Synca")
                    .font(.system(size: 17, weight: .semibold))

                if let status = accessManager.status {
                    Button {
                        accessManager.showAccessCenter = true
                    } label: {
                        HeaderAccessBadge(status: status)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    #endif

    // MARK: - Subviews

    private var isTiledLayout: Bool {
        #if os(macOS)
        settings.messageListLayoutMode == .tiled
        #else
        false
        #endif
    }

    private var selectedFilterCategoryId: String? {
        let selected = syncManager.selectedCategoryId
        if selected == syncManager.allCategoryPseudoId {
            return nil
        }
        return selected
    }

    private var activeSendCategoryId: String? {
        if syncManager.selectedCategoryId == syncManager.allCategoryPseudoId {
            return syncManager.defaultSendCategoryId()
        }
        return syncManager.selectedCategoryId
    }

    private var filteredMessages: [SyncaMessage] {
        syncManager.messages(for: selectedFilterCategoryId)
    }

    private var clearActionMessage: String {
        if isTiledLayout {
            return String(localized: "message_list.clear_completed_all_categories", bundle: .main)
        }
        if let category = syncManager.categories.first(where: { $0.id == selectedFilterCategoryId }) {
            return String(
                format: String(localized: "message_list.clear_completed_category_format", bundle: .main),
                category.name
            )
        }
        return String(localized: "message_list.clear_completed_all_messages", bundle: .main)
    }

    @ViewBuilder
    private var categoryToolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: String(localized: "common.all", bundle: .main), color: .secondary.opacity(0.16), isSelected: syncManager.selectedCategoryId == syncManager.allCategoryPseudoId) {
                    syncManager.selectCategory(syncManager.allCategoryPseudoId)
                }

                ForEach(syncManager.categories) { category in
                    categoryChip(title: category.name, color: backgroundColor(for: category.color), isSelected: syncManager.selectedCategoryId == category.id) {
                        syncManager.selectCategory(category.id)
                    }
                }

                Button {
                    showCategoryManager = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
    }

    private func categoryChip(title: String, color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(color)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.primary.opacity(0.18) : Color.clear, lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func categoryBadge(name: String, color: MessageCategoryColor) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(categoryAccentColor(for: color))
                .frame(width: 8, height: 8)

            Text(name)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(backgroundColor(for: color))
        .clipShape(Capsule())
    }

    private func categoryAccentColor(for color: MessageCategoryColor) -> Color {
        switch color {
        case .sky:
            return .blue
        case .mint:
            return .green
        case .amber:
            return .orange
        case .coral:
            return .red
        case .violet:
            return .purple
        case .slate:
            return .secondary
        case .rose:
            return .pink
        case .ocean:
            return .cyan
        }
    }

    private func backgroundColor(for color: MessageCategoryColor) -> Color {
        switch color {
        case .sky:
            return Color.blue.opacity(0.16)
        case .mint:
            return Color.green.opacity(0.16)
        case .amber:
            return Color.orange.opacity(0.18)
        case .coral:
            return Color.red.opacity(0.16)
        case .violet:
            return Color.purple.opacity(0.18)
        case .slate:
            return Color.secondary.opacity(0.16)
        case .rose:
            return Color.pink.opacity(0.16)
        case .ocean:
            return Color.cyan.opacity(0.18)
        }
    }

    @ViewBuilder
    private var messageList: some View {
        let completed = filteredMessages.filter { $0.isCleared }
        let uncompleted = filteredMessages.filter { !$0.isCleared }

        if !syncManager.hasCompletedInitialLoad {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if completed.isEmpty && uncompleted.isEmpty {
            emptyStateView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(completed) { message in
                            messageView(for: message)
                        }

                        if !uncompleted.isEmpty {
                            HStack {
                                Text("message_list.todo_section", bundle: .main)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                Spacer()
                            }
                            .padding(.top, 8)
                            .id("uncompleted_header")

                            ForEach(uncompleted) { message in
                                messageView(for: message)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: filteredMessages)
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                #if os(iOS)
                                hideKeyboard()
                                #endif
                            }
                    )

                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                #if os(iOS)
                .scrollDismissesKeyboard(.immediately)
                .refreshable {
                    let task = Task {
                        await syncManager.refresh()
                    }
                    _ = await task.result
                }
                #endif
                .onChange(of: syncManager.isSending) { isSending in
                    guard !isSending, shouldScrollToBottomAfterSend else { return }
                    beginPostSendScrollWindow()
                    scrollToBottomAfterLayoutSettles(proxy: proxy)
                }
                .onChange(of: syncManager.hasCompletedInitialLoad) { hasCompletedInitialLoad in
                    guard hasCompletedInitialLoad, !filteredMessages.isEmpty else { return }
                    beginInitialLoadScrollWindow()
                    scrollToBottomAfterLayoutSettles(proxy: proxy)
                }
                .onChange(of: filteredMessages.count) { _ in
                    guard shouldScrollToBottomAfterInitialLoad else { return }
                    scrollToBottomAfterLayoutSettles(proxy: proxy)
                }
                .onReceive(NotificationCenter.default.publisher(for: .syncaScrollToBottomAfterImageLoad)) { _ in
                    guard shouldScrollToBottomAfterSend || shouldScrollToBottomAfterInitialLoad else { return }
                    scrollToBottomAfterLayoutSettles(proxy: proxy)
                }
                .onChange(of: syncManager.remoteAppendEvent) { _ in
                    guard syncManager.hasCompletedInitialLoad else { return }
                    scrollToBottomAfterLayoutSettles(proxy: proxy)
                }
                .onAppear {
                    if syncManager.hasCompletedInitialLoad && !filteredMessages.isEmpty {
                        beginInitialLoadScrollWindow()
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        proxy.scrollTo("bottom", anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var syncStatusOverlay: some View {
        #if os(iOS)
        let topInset: CGFloat = 58
        #else
        let topInset: CGFloat = 16
        #endif

        Group {
            if case .success = self.syncManager.syncStatus {
                Label("message_list.sync_success", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.green)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                    .padding(.top, topInset)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if case .error(let message) = self.syncManager.syncStatus {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                    Text(message)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                .padding(.top, topInset)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: self.syncManager.syncStatus)
    }

    @ViewBuilder
    private var loadingOverlay: some View {
        if self.syncManager.isLoading && self.syncManager.messages.isEmpty {
            ProgressView("message_list.loading")
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    @ViewBuilder
    private var feedbackToastOverlay: some View {
        #if os(iOS)
        let topInset: CGFloat = 58
        #else
        let topInset: CGFloat = 16
        #endif

        if showFeedbackSuccessToast {
            Label("feedback.submit_success", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green)
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                .padding(.top, topInset)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text("Synca")
                .font(.system(size: 24, weight: .semibold))
                .foregroundColor(.primary)

            Text("app.slogan", bundle: .main)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Toolbar Items

    private var refreshButton: some View {
        Button {
            Task { await self.syncManager.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .buttonStyle(.plain)
        .disabled(self.syncManager.isRefreshing)
    }

    private var clearAllButton: some View {
        Button {
            self.showClearAllConfirm = true
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.plain)
        .disabled((isTiledLayout ? syncManager.messages : filteredMessages).allSatisfy { !$0.isCleared })
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                self.showAccountInfo = true
            } label: {
                Label("account.section_title", systemImage: "person.crop.circle")
            }

            Button {
                showCategoryManager = true
            } label: {
                Label("message_list.manage_categories", systemImage: "tag")
            }

            Button {
                showFeedbackComposer = true
            } label: {
                Label("message_list.feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }

            Button {
                self.showAboutInfo = true
            } label: {
                Label("message_list.about", systemImage: "info.circle")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    private var layoutToggleButton: some View {
        Button {
            settings.setMessageListLayoutMode(settings.messageListLayoutMode == .single ? .tiled : .single)
        } label: {
            Image(systemName: settings.messageListLayoutMode == .single ? "square.grid.2x2" : "rectangle.split.3x1")
        }
        .buttonStyle(.plain)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 9, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isSending)
            .opacity(syncManager.isSending ? 0.5 : 1.0)
            .onChange(of: self.selectedPhotoItems) { items in
                guard !items.isEmpty else { return }
                Task {
                    // Reverse the order so the 'newest' (usually selected first) 
                    // appears at the bottom of the chat list
                    let reversedItems = items.reversed()
                    var imageDatas: [Data] = []
                    for item in reversedItems {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            imageDatas.append(data)
                        }
                    }
                    self.selectedPhotoItems = []
                    if !imageDatas.isEmpty {
                        shouldScrollToBottomAfterSend = true
                        await self.syncManager.sendImages(imageDatas, categoryId: activeSendCategoryId)
                    }
                }
            }

            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 20, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isSending)
            .opacity(syncManager.isSending ? 0.5 : 1.0)

            #if os(iOS)
            inputField
            #else
            inputField
            #endif

            Button {
                self.submitText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(self.canSend ? Color.accentColor : Color.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        #if os(macOS)
        .padding(.vertical, 8)
        #else
        .padding(.top, 10)
        .padding(.bottom, 6)
        #endif
        #if os(iOS)
        .background(.bar)
        #else
        .background(Color.syncaPageBackground)
        #endif
    }

    @ViewBuilder
    private var inputField: some View {
        #if os(iOS)
        ZStack(alignment: .leading) {
            PasteAwareTextView(text: $inputText, height: $inputHeight, isSending: syncManager.isSending, onImagePaste: { imageData in
                shouldScrollToBottomAfterSend = true
                Task { await syncManager.sendImage(imageData, categoryId: activeSendCategoryId) }
            }, onFilePaste: { pendingFile in
                shouldScrollToBottomAfterSend = true
                Task { await sendPendingFile(pendingFile, categoryId: activeSendCategoryId) }
            }, onSubmit: {
                self.submitText()
            })
            .frame(height: max(44, min(inputHeight, 150)))
            .opacity(syncManager.isSending ? 0.5 : 1.0)

            if inputText.isEmpty {
                Text(syncManager.isSending ? "message_list.sending_placeholder" : "message_list.input_placeholder", bundle: .main)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 8)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(Color.secondary.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 20))
        #else
        ZStack(alignment: .leading) {
            MacInputTextView(text: $inputText, height: $inputHeight, isSending: syncManager.isSending, onPasteImage: { imageData in
                shouldScrollToBottomAfterSend = true
                Task { await syncManager.sendImage(imageData, categoryId: activeSendCategoryId) }
            }, onPasteFile: { pendingFile in
                shouldScrollToBottomAfterSend = true
                Task { await sendPendingFile(pendingFile, categoryId: activeSendCategoryId) }
            }, onSubmit: {
                self.submitText()
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(34, min(inputHeight, 104)))
            .opacity(syncManager.isSending ? 0.5 : 1.0)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)

            if inputText.isEmpty {
                Text(syncManager.isSending ? "message_list.sending_placeholder" : "message_list.input_placeholder", bundle: .main)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
                    .padding(.top, 1)
                    .allowsHitTesting(false)
            }
        }
        .background(Color.syncaInputFieldBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color.syncaInputFieldBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        #endif
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !syncManager.isSending
    }

    private var defaultComposerHeight: CGFloat {
        #if os(iOS)
        44
        #else
        34
        #endif
    }

    private func submitText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputHeight = defaultComposerHeight
        shouldScrollToBottomAfterSend = true
        Task {
            let result = await syncManager.sendText(text, categoryId: activeSendCategoryId)
            if result != .sent {
                inputText = text
            }
        }
    }

    @MainActor
    private func deleteAccount() async {
        do {
            try await api.deleteAccount()
            showDeleteAccountSuccess = true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(localized: "account.delete_failed_message", bundle: .main)
            deleteAccountErrorMessage = message
        }
    }

    private var supportedDocumentTypes: [UTType] {
        [
            .pdf,
            .plainText,
            .text,
            .commaSeparatedText,
            UTType(filenameExtension: "doc"),
            UTType(filenameExtension: "docx"),
            UTType(filenameExtension: "xls"),
            UTType(filenameExtension: "xlsx"),
            UTType(filenameExtension: "ppt"),
            UTType(filenameExtension: "pptx"),
            UTType(filenameExtension: "md"),
            UTType(filenameExtension: "zip"),
        ].compactMap { $0 }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        shouldScrollToBottomAfterSend = true

        for url in urls {
            guard let pendingFile = readPendingFile(from: url) else { continue }
            await sendPendingFile(pendingFile, categoryId: activeSendCategoryId)
        }
    }

    private func readPendingFile(from url: URL) -> PendingFileUpload? {
        let startedAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if startedAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
        return PendingFileUpload(data: data, fileName: url.lastPathComponent, mimeType: mimeType)
    }

    private func sendPendingFile(_ pendingFile: PendingFileUpload, categoryId: String?) async {
        await syncManager.sendFile(data: pendingFile.data, fileName: pendingFile.fileName, mimeType: pendingFile.mimeType, categoryId: categoryId)
    }

    private func scrollToBottomAfterLayoutSettles(proxy: ScrollViewProxy) {
        let delays: [TimeInterval] = [0, 0.10, 0.24, 0.45]

        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
        }
    }

    private func beginPostSendScrollWindow() {
        let windowID = UUID()
        postSendScrollWindowID = windowID

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if postSendScrollWindowID == windowID {
                shouldScrollToBottomAfterSend = false
            }
        }
    }

    private func beginInitialLoadScrollWindow() {
        let windowID = UUID()
        initialLoadScrollWindowID = windowID
        shouldScrollToBottomAfterInitialLoad = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if initialLoadScrollWindowID == windowID {
                shouldScrollToBottomAfterInitialLoad = false
            }
        }
    }

    // [Removed] compressImageData: No longer needed. All bytes are now handled losslessly.

    @MainActor
    private func updateBadge() {
        let count = syncManager.unclearedCount
        #if os(iOS)
        if #available(iOS 17.0, *) {
            UNUserNotificationCenter.current().setBadgeCount(count)
        } else {
            UIApplication.shared.applicationIconBadgeNumber = count
        }
        #elseif os(macOS)
        if count > 0 {
            NSApp.dockTile.badgeLabel = "\(count)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
        #endif
    }
    
    #if os(macOS)
    private func handlePasteShortcut() {
        let pb = NSPasteboard.general

        if let rawPngData = pb.data(forType: .png) {
            shouldScrollToBottomAfterSend = true
            Task { await syncManager.sendImage(rawPngData, categoryId: activeSendCategoryId) }
            return
        }
        if let rawJpegData = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            shouldScrollToBottomAfterSend = true
            Task { await syncManager.sendImage(rawJpegData, categoryId: activeSendCategoryId) }
            return
        }
        if let rawHeicData = pb.data(forType: NSPasteboard.PasteboardType("public.heic")) {
            shouldScrollToBottomAfterSend = true
            Task { await syncManager.sendImage(rawHeicData, categoryId: activeSendCategoryId) }
            return
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:]) {
            shouldScrollToBottomAfterSend = true
            Task { await syncManager.sendImage(pngData, categoryId: activeSendCategoryId) }
            return
        }

        if let fileURL = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL,
           let pendingFile = readPendingFile(from: fileURL) {
            shouldScrollToBottomAfterSend = true
            Task { await sendPendingFile(pendingFile, categoryId: activeSendCategoryId) }
            return
        }

        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }
    #endif

    #if os(iOS)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif

    @ViewBuilder
    private func messageView(for message: SyncaMessage) -> some View {
        MessageBubbleView(
            message: message,
            categories: syncManager.categories,
            onClear: {
                Task { await syncManager.clearMessage(message.id) }
            },
            onDelete: {
                Task { await syncManager.deleteMessage(message.id) }
            },
            onCategoryChange: { categoryId in
                Task { await syncManager.updateMessageCategory(message.id, categoryId: categoryId) }
            },
            onImageTap: {
                selectedImageMessage = message
            },
            onImageLoaded: {
                guard shouldScrollToBottomAfterSend || shouldScrollToBottomAfterInitialLoad else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    NotificationCenter.default.post(name: .syncaScrollToBottomAfterImageLoad, object: nil)
                }
            }
        )
        .id("\(message.id)-\(message.isCleared)")
    }

    @ViewBuilder
    private var tiledBoardView: some View {
        GeometryReader { proxy in
            let spacing: CGFloat = 16
            let horizontalPadding: CGFloat = 32
            let columnCount = max(CGFloat(syncManager.categories.count), 1)
            let availableWidth = max(proxy.size.width - horizontalPadding, TiledCategoryColumn.minWidth)
            let sharedWidth = max(
                TiledCategoryColumn.minWidth,
                floor((availableWidth - spacing * max(columnCount - 1, 0)) / columnCount)
            )

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(syncManager.categories) { category in
                        TiledCategoryColumn(category: category)
                            .environmentObject(syncManager)
                            .frame(width: sharedWidth)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
    }

    private func handleTopClearAction() async {
        if isTiledLayout {
            await syncManager.clearCompleted(categoryId: nil)
        } else {
            await syncManager.clearCompleted(categoryId: selectedFilterCategoryId)
        }
    }
}

private struct TiledCategoryColumn: View {
    static let minWidth: CGFloat = 420

    @EnvironmentObject var syncManager: SyncManager
    let category: SyncaMessageCategory

    @State private var inputText = ""
    @State private var inputHeight: CGFloat = 34
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false

    private var messages: [SyncaMessage] {
        syncManager.messages(for: category.id)
    }

    private var completedMessages: [SyncaMessage] {
        messages.filter(\.isCleared)
    }

    private var pendingMessages: [SyncaMessage] {
        messages.filter { !$0.isCleared }
    }

    private var emptyStateView: some View {
        VStack(spacing: 14) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Synca")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.primary)

            Text("app.slogan", bundle: .main)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(category.name)
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(backgroundColor(for: category.color))
                    .clipShape(Capsule())

                Spacer()

                Button {
                    Task { await syncManager.fullSync(manual: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)

                Button {
                    Task { await syncManager.clearCompleted(categoryId: category.id) }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .disabled(completedMessages.isEmpty)
            }
            .padding(14)

            if completedMessages.isEmpty && pendingMessages.isEmpty {
                emptyStateView
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(completedMessages) { message in
                            MessageBubbleView(
                                message: message,
                                categories: syncManager.categories,
                                onClear: {},
                                onDelete: {
                                    Task { await syncManager.deleteMessage(message.id) }
                                },
                                onCategoryChange: { categoryId in
                                    Task { await syncManager.updateMessageCategory(message.id, categoryId: categoryId) }
                                },
                                onImageTap: {},
                                onImageLoaded: {}
                            )
                        }

                        if !pendingMessages.isEmpty {
                            HStack {
                                Text("message_list.todo_section", bundle: .main)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.1))
                                    .cornerRadius(4)
                                Spacer()
                            }
                        }

                        ForEach(pendingMessages) { message in
                            MessageBubbleView(
                                message: message,
                                categories: syncManager.categories,
                                onClear: {
                                    Task { await syncManager.clearMessage(message.id) }
                                },
                                onDelete: {
                                    Task { await syncManager.deleteMessage(message.id) }
                                },
                                onCategoryChange: { categoryId in
                                    Task { await syncManager.updateMessageCategory(message.id, categoryId: categoryId) }
                                },
                                onImageTap: {},
                                onImageLoaded: {}
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }

            Divider()

            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 9, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18))
                }
                .buttonStyle(.plain)
                .disabled(syncManager.isSending)
                .opacity(syncManager.isSending ? 0.5 : 1.0)
                .onChange(of: selectedPhotoItems) { items in
                    guard !items.isEmpty else { return }
                    Task {
                        let reversedItems = items.reversed()
                        var imageDatas: [Data] = []
                        for item in reversedItems {
                            if let data = try? await item.loadTransferable(type: Data.self) {
                                imageDatas.append(data)
                            }
                        }
                        selectedPhotoItems = []
                        if !imageDatas.isEmpty {
                            await syncManager.sendImages(imageDatas, categoryId: category.id)
                        }
                    }
                }

                Button {
                    showFileImporter = true
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 17, weight: .medium))
                }
                .buttonStyle(.plain)
                .disabled(syncManager.isSending)
                .opacity(syncManager.isSending ? 0.5 : 1.0)

#if os(macOS)
                ZStack(alignment: .leading) {
                    MacInputTextView(
                        text: $inputText,
                        height: $inputHeight,
                        isSending: syncManager.isSending,
                        onPasteImage: { imageData in
                            Task { await syncManager.sendImage(imageData, categoryId: category.id) }
                        },
                        onPasteFile: { pendingFile in
                            Task {
                                await syncManager.sendFile(
                                    data: pendingFile.data,
                                    fileName: pendingFile.fileName,
                                    mimeType: pendingFile.mimeType,
                                    categoryId: category.id
                                )
                            }
                        },
                        onSubmit: submitText
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: max(34, min(inputHeight, 104)))
                    .opacity(syncManager.isSending ? 0.5 : 1.0)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)

                    if inputText.isEmpty {
                        Text("message_list.input_placeholder", bundle: .main)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 12)
                            .padding(.top, 1)
                            .allowsHitTesting(false)
                    }
                }
                .background(Color.syncaInputFieldBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.syncaInputFieldBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
#else
                TextField(String(localized: "message_list.input_placeholder", bundle: .main), text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color.syncaInputFieldBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.syncaInputFieldBorder, lineWidth: 1)
                    )
#endif

                Button {
                    submitText()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || syncManager.isSending)
            }
            .padding(14)
            .background(Color.syncaPageBackground)
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: supportedDocumentTypes,
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImportedFiles(result) }
        }
        .background(Color.syncaCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.syncaCardBorder, lineWidth: 1)
        )
    }

    private func backgroundColor(for color: MessageCategoryColor) -> Color {
        switch color {
        case .sky:
            return Color.blue.opacity(0.16)
        case .mint:
            return Color.green.opacity(0.16)
        case .amber:
            return Color.orange.opacity(0.18)
        case .coral:
            return Color.red.opacity(0.16)
        case .violet:
            return Color.purple.opacity(0.18)
        case .slate:
            return Color.secondary.opacity(0.16)
        case .rose:
            return Color.pink.opacity(0.16)
        case .ocean:
            return Color.cyan.opacity(0.18)
        }
    }

    private var supportedDocumentTypes: [UTType] {
        [
            .pdf,
            .plainText,
            .text,
            .commaSeparatedText,
            UTType(filenameExtension: "doc"),
            UTType(filenameExtension: "docx"),
            UTType(filenameExtension: "xls"),
            UTType(filenameExtension: "xlsx"),
            UTType(filenameExtension: "ppt"),
            UTType(filenameExtension: "pptx"),
            UTType(filenameExtension: "md"),
            .zip
        ].compactMap { $0 }
    }

    private func handleImportedFiles(_ result: Result<[URL], Error>) async {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard let pendingFile = readPendingFile(from: url) else { continue }
            await syncManager.sendFile(
                data: pendingFile.data,
                fileName: pendingFile.fileName,
                mimeType: pendingFile.mimeType,
                categoryId: category.id
            )
        }
    }

    private func readPendingFile(from url: URL) -> PendingFileUpload? {
        let needsSecurityScope = url.startAccessingSecurityScopedResource()
        defer {
            if needsSecurityScope {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else { return nil }
        let mimeType = UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType
        return PendingFileUpload(data: data, fileName: url.lastPathComponent, mimeType: mimeType)
    }

    private func submitText() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        inputHeight = 34
        Task {
            let result = await syncManager.sendText(text, categoryId: category.id)
            if result != .sent {
                inputText = text
            }
        }
    }
}

private struct MessageCategoryManagerSheet: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var newCategoryName = ""
    @State private var newCategoryColor: MessageCategoryColor = .sky
    @State private var draftNames: [String: String] = [:]
    private let cardCornerRadius: CGFloat = 18

    private func colorName(for color: MessageCategoryColor) -> LocalizedStringKey {
        switch color {
        case .sky:
            return "message_category.color.sky"
        case .mint:
            return "message_category.color.mint"
        case .amber:
            return "message_category.color.amber"
        case .coral:
            return "message_category.color.coral"
        case .violet:
            return "message_category.color.violet"
        case .slate:
            return "message_category.color.slate"
        case .rose:
            return "message_category.color.rose"
        case .ocean:
            return "message_category.color.ocean"
        }
    }

    @ViewBuilder
    private func colorOptionRow(_ color: MessageCategoryColor) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(colorAccent(color))
                .frame(width: 10, height: 10)
            Text(colorName(for: color))
        }
    }

    private func colorAccent(_ color: MessageCategoryColor) -> Color {
        switch color {
        case .sky:
            return .blue
        case .mint:
            return .green
        case .amber:
            return .orange
        case .coral:
            return .red
        case .violet:
            return .purple
        case .slate:
            return .secondary
        case .rose:
            return .pink
        case .ocean:
            return .cyan
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("message_category.new_section", bundle: .main)
                            .font(.headline)

                        TextField(String(localized: "message_category.name_placeholder", bundle: .main), text: $newCategoryName)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color.syncaInputFieldBackground, in: RoundedRectangle(cornerRadius: 14))
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.syncaInputFieldBorder, lineWidth: 1)
                            )

                        colorPickerField(selection: $newCategoryColor)

                        Button("message_category.add_action") {
                            let trimmed = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            Task {
                                await syncManager.createCategory(name: trimmed, color: newCategoryColor)
                                newCategoryName = ""
                                newCategoryColor = .sky
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(18)
                    .background(Color.syncaCardBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: cardCornerRadius)
                            .stroke(Color.syncaCardBorder, lineWidth: 1)
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text("message_category.section_title", bundle: .main)
                            .font(.headline)

                        ForEach(syncManager.categories) { category in
                            VStack(alignment: .leading, spacing: 14) {
                                HStack(alignment: .center, spacing: 10) {
                                    categoryBadge(name: category.name, color: category.color)
                                    Spacer()
                                    defaultSendToggle(for: category)
                                }

                                if !category.isDefault {
                                    TextField(
                                        String(localized: "message_category.name_placeholder", bundle: .main),
                                        text: Binding(
                                            get: { draftNames[category.id] ?? category.name },
                                            set: { draftNames[category.id] = $0 }
                                        )
                                    )
                                    .textFieldStyle(.plain)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.syncaInputFieldBackground, in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14)
                                            .stroke(Color.syncaInputFieldBorder, lineWidth: 1)
                                    )

                                    colorPickerField(
                                        selection: Binding(
                                            get: { category.color },
                                            set: { newValue in
                                                Task { await syncManager.updateCategory(id: category.id, color: newValue) }
                                            }
                                        )
                                    )

                                    HStack {
                                        Button("message_category.save_name") {
                                            let name = (draftNames[category.id] ?? category.name).trimmingCharacters(in: .whitespacesAndNewlines)
                                            guard !name.isEmpty, name != category.name else { return }
                                            Task { await syncManager.updateCategory(id: category.id, name: name) }
                                        }
                                        .buttonStyle(.bordered)

                                        Spacer()

                                        Button(role: .destructive) {
                                            Task { await syncManager.deleteCategory(id: category.id) }
                                        } label: {
                                            Text("message_category.delete_action", bundle: .main)
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                            .padding(18)
                            .background(Color.syncaCardBackground, in: RoundedRectangle(cornerRadius: cardCornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: cardCornerRadius)
                                    .stroke(Color.syncaCardBorder, lineWidth: 1)
                            )
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("message_category.section_title")
            #if os(macOS)
            .frame(minWidth: 620, minHeight: 520)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done") { dismiss() }
                }
            }
        }
        .onAppear {
            draftNames = Dictionary(uniqueKeysWithValues: syncManager.categories.map { ($0.id, $0.name) })
        }
    }

    @ViewBuilder
    private func defaultSendToggle(for category: SyncaMessageCategory) -> some View {
        Button {
            syncManager.setDefaultSendCategoryId(category.id)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: syncManager.defaultSendCategoryId() == category.id ? "largecircle.fill.circle" : "circle")
                Text("message_list.default_send_category", bundle: .main)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func colorPickerField(selection: Binding<MessageCategoryColor>) -> some View {
        Picker("message_category.color_label", selection: selection) {
            ForEach(MessageCategoryColor.allCases) { color in
                colorOptionRow(color).tag(color)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.syncaInputFieldBackground, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.syncaInputFieldBorder, lineWidth: 1)
        )
    }

    private func categoryBadge(name: String, color: MessageCategoryColor) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(colorAccent(color))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(colorAccent(color).opacity(0.16))
        .clipShape(Capsule())
    }
}

private struct AboutSyncaSheet: View {
    @Environment(\.dismiss) private var dismiss

    private let websiteURL = URL(string: "https://synca.haerth.cn/")!

    #if os(iOS)
    private let systemLinkColor = Color(uiColor: .link)
    #elseif os(macOS)
    private let systemLinkColor = Color(nsColor: .linkColor)
    #endif

    private var sheetBackgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(
            format: String(localized: "message_list.about_version_format", bundle: .main),
            version,
            build
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 14) {
                        Image("LoginLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 14, y: 8)

                        VStack(spacing: 6) {
                            Text("Synca")
                                .font(.title2.weight(.semibold))

                            Text(String(localized: "app.slogan", bundle: .main))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)

                    VStack(alignment: .leading, spacing: 16) {
                        Text(versionText)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Divider()

                        Link(destination: websiteURL) {
                            HStack(alignment: .center, spacing: 12) {
                                Text(websiteURL.absoluteString)
                                    .font(.body)
                                    .foregroundStyle(systemLinkColor)
                                    .multilineTextAlignment(.leading)

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("message_list.about_website_hint"))
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .background(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.10),
                        sheetBackgroundColor
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle(Text("message_list.about"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("message_list.got_it") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 460, minHeight: 360, idealHeight: 380)
        #endif
    }
}

private struct AccountSheet: View {
    @Environment(\.dismiss) private var dismiss

    let accountEmail: String?
    let onRequestDeleteAccount: () -> Void
    let onRequestSignOut: () -> Void

    private var normalizedAccountEmail: String? {
        let trimmed = accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var isPrivateRelayEmail: Bool {
        guard let normalizedAccountEmail else { return false }
        return normalizedAccountEmail.localizedCaseInsensitiveContains("privaterelay.appleid.com")
    }

    private var resolvedAccountEmail: String {
        normalizedAccountEmail
            ?? String(localized: "account.email_unavailable", bundle: .main)
    }

    private func runAfterDismiss(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            action()
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 36, height: 36)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("account.provider.apple", bundle: .main)
                                    .font(.subheadline.weight(.semibold))

                                if isPrivateRelayEmail {
                                    Label {
                                        Text("account.email_hidden_title", bundle: .main)
                                    } icon: {
                                        Image(systemName: "eye.slash.fill")
                                    }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                    Text("account.email_hidden_message", bundle: .main)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                } else {
                                    Text(resolvedAccountEmail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .multilineTextAlignment(.leading)
                                }
                            }

                            Spacer(minLength: 0)
                        }

                        Divider()

                        Button {
                            runAfterDismiss(onRequestSignOut)
                        } label: {
                            accountActionRow(
                                title: String(localized: "message_list.sign_out", bundle: .main),
                                systemImage: "rectangle.portrait.and.arrow.right",
                                tint: .primary
                            )
                        }
                        .buttonStyle(.plain)

                        Button(role: .destructive) {
                            runAfterDismiss(onRequestDeleteAccount)
                        } label: {
                            accountActionRow(
                                title: String(localized: "account.delete_action", bundle: .main),
                                systemImage: "person.crop.circle.badge.xmark",
                                tint: .red
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .navigationTitle(Text("account.section_title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("message_list.got_it") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 460, minHeight: 280, idealHeight: 320)
        #endif
    }

    @ViewBuilder
    private func accountActionRow(title: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 24)

            Text(title)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }
}

extension View {
    @ViewBuilder
    func imagePreviewSheet(item: Binding<SyncaMessage?>, syncManager: SyncManager) -> some View {
        #if os(iOS)
        self.fullScreenCover(item: item) { msg in
            let allImages = syncManager.imageMessages
            let initialIndex = allImages.firstIndex(where: { $0.id == msg.id }) ?? 0
            ImagePreviewView(messages: allImages, initialIndex: initialIndex) { deletedId in
                Task { await syncManager.deleteMessage(deletedId) }
            }
        }
        #else
        self.sheet(item: item) { msg in
            let allImages = syncManager.imageMessages
            let initialIndex = allImages.firstIndex(where: { $0.id == msg.id }) ?? 0
            ImagePreviewView(messages: allImages, initialIndex: initialIndex) { deletedId in
                Task { await syncManager.deleteMessage(deletedId) }
            }
            .frame(minWidth: 800, minHeight: 600)
        }
        #endif
    }
}
