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
    @State private var showCreateCategory = false
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
            .sheet(isPresented: $showCreateCategory) {
                NewMessageCategorySheet {
                    showCreateCategory = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        showCategoryManager = true
                    }
                }
                    .environmentObject(syncManager)
                    #if os(iOS)
                    .presentationDetents([.height(430), .large])
                    .presentationDragIndicator(.visible)
                    #endif
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
            allowedContentTypes: supportedAttachmentTypes,
            allowsMultipleSelection: true
        ) { result in
            Task { await handleImportedFiles(result) }
        }
        .imagePreviewSheet(item: $selectedImageMessage, syncManager: syncManager)
        .task {
            shouldScrollToBottomAfterInitialLoad = true
            syncManager.restoreCachedDataIfAvailable()
            
            let pm = purchaseManager
            Task.detached(priority: .background) {
                await PushTokenManager.shared.uploadCachedTokenIfPossible()
                await pm.loadProducts()
                _ = try? await pm.syncLatestTransactions()
            }
            
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
        .onChange(of: syncManager.errorMessage) { message in
            guard message != nil else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                syncManager.errorMessage = nil
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

    private var allTodoCount: Int {
        syncManager.messages.filter { !$0.isCleared }.count
    }

    private func todoCount(for categoryId: String?) -> Int {
        syncManager.messages(for: categoryId).filter { !$0.isCleared }.count
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
                categoryChip(
                    title: String(localized: "common.all", bundle: .main),
                    color: .secondary.opacity(0.16),
                    isSelected: syncManager.selectedCategoryId == syncManager.allCategoryPseudoId,
                    badgeCount: allTodoCount
                ) {
                    syncManager.selectCategory(syncManager.allCategoryPseudoId)
                }

                ForEach(syncManager.categories) { category in
                    categoryChip(
                        title: category.isDefault ? String(localized: "message_category.default_badge", bundle: .main) : category.name,
                        color: backgroundColor(for: category.color),
                        isSelected: syncManager.selectedCategoryId == category.id,
                        badgeCount: todoCount(for: category.id)
                    ) {
                        syncManager.selectCategory(category.id)
                    }
                }

                Button {
                    showCreateCategory = true
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
            .padding(.top, 7)
        }
        .padding(.vertical, 10)
    }

    private func categoryChip(title: String, color: Color, isSelected: Bool, badgeCount: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(color)
                .overlay(
                    Capsule()
                        .stroke(isSelected ? Color.primary.opacity(0.4) : Color.clear, lineWidth: 1.5)
                )
                .clipShape(Capsule())
                .opacity(isSelected ? 1.0 : 0.45)
                .overlay(alignment: .topTrailing) {
                if badgeCount > 0 {
                    todoCountBadge(badgeCount)
                        .offset(x: 8, y: -7)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func todoCountBadge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, count > 9 ? 5 : 0)
            .frame(minWidth: 17, minHeight: 17)
            .background(Color.red, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.syncaPageBackground.opacity(0.9), lineWidth: 1)
            )
            .accessibilityLabel(Text("\(count) todos"))
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

        if let errorMessage = syncManager.errorMessage {
            Label {
                Text(errorMessage)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            } icon: {
                Image(systemName: "xmark.circle.fill")
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
        } else if showFeedbackSuccessToast {
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

    private var supportedAttachmentTypes: [UTType] {
        [
            .image,
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
            if let imageData = PendingFileUpload.imageData(from: url) {
                await syncManager.sendImage(imageData, categoryId: activeSendCategoryId)
                continue
            }

            guard let pendingFile = readPendingFile(from: url) else {
                syncManager.errorMessage = unsupportedAttachmentMessage(for: url)
                continue
            }
            await sendPendingFile(pendingFile, categoryId: activeSendCategoryId)
        }
    }

    private func readPendingFile(from url: URL) -> PendingFileUpload? {
        PendingFileUpload.read(from: url)
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

        if let fileURL = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL {
            shouldScrollToBottomAfterSend = true
            if let imageData = PendingFileUpload.imageData(from: fileURL) {
                Task { await syncManager.sendImage(imageData, categoryId: activeSendCategoryId) }
            } else if let pendingFile = readPendingFile(from: fileURL) {
                Task { await sendPendingFile(pendingFile, categoryId: activeSendCategoryId) }
            } else {
                syncManager.errorMessage = unsupportedAttachmentMessage(for: fileURL)
            }
            return
        }

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
                            .id(category.id)
                            .frame(width: sharedWidth)
                    }
                }
                .padding(16)
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

private func unsupportedAttachmentMessage(for url: URL) -> String {
    let ext = url.pathExtension.lowercased()
    if PendingFileUpload.supportedImageExtensions.contains(ext) {
        return String(localized: "message_file.error_image_too_large", bundle: .main)
    }
    if PendingFileUpload.supportedExtensions.contains(ext) {
        return String(localized: "message_file.error_too_large", bundle: .main)
    }
    return String(localized: "message_file.error_unsupported", bundle: .main)
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

    private func todoCountBadge(_ count: Int) -> some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, count > 9 ? 5 : 0)
            .frame(minWidth: 17, minHeight: 17)
            .background(Color.red, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.syncaCardBackground.opacity(0.9), lineWidth: 1)
            )
            .accessibilityLabel(Text("\(count) todos"))
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
                Text(category.isDefault ? String(localized: "message_category.default_badge", bundle: .main) : category.name)
                    .font(.headline)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(backgroundColor(for: category.color))
                    .clipShape(Capsule())
                    .overlay(alignment: .topTrailing) {
                    if pendingMessages.count > 0 {
                        todoCountBadge(pendingMessages.count)
                            .offset(x: 8, y: -7)
                    }
                }

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
            .padding(.horizontal, 14)
            .padding(.top, 21)
            .padding(.bottom, 14)

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

#if os(macOS)
            MacTiledComposerBar(
                text: $inputText,
                height: $inputHeight,
                isSending: syncManager.isSending,
                onImageData: { imageData in
                    Task { await syncManager.sendImage(imageData, categoryId: category.id) }
                },
                onFile: { pendingFile in
                    Task {
                        await syncManager.sendFile(
                            data: pendingFile.data,
                            fileName: pendingFile.fileName,
                            mimeType: pendingFile.mimeType,
                            categoryId: category.id
                        )
                    }
                },
                onUnsupportedFile: { url in
                    syncManager.errorMessage = unsupportedAttachmentMessage(for: url)
                },
                onSubmit: submitText
            )
            .frame(height: max(52, min(inputHeight + 18, 122)))
            .padding(14)
            .background(Color.syncaPageBackground)
#else
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 9, matching: .images) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 18))
                        .frame(width: 24, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(syncManager.isSending)
                .opacity(syncManager.isSending ? 0.5 : 1.0)
                .zIndex(2)
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
                        .frame(width: 22, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(syncManager.isSending)
                .opacity(syncManager.isSending ? 0.5 : 1.0)
                .zIndex(2)

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

                Button {
                    submitText()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 28))
                        .frame(width: 30, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || syncManager.isSending)
                .zIndex(2)
            }
            .padding(14)
            .background(Color.syncaPageBackground)
#endif
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: supportedAttachmentTypes,
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

    private var supportedAttachmentTypes: [UTType] {
        [
            .image,
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
            if let imageData = PendingFileUpload.imageData(from: url) {
                await syncManager.sendImage(imageData, categoryId: category.id)
                continue
            }

            guard let pendingFile = readPendingFile(from: url) else {
                syncManager.errorMessage = unsupportedAttachmentMessage(for: url)
                continue
            }
            await syncManager.sendFile(
                data: pendingFile.data,
                fileName: pendingFile.fileName,
                mimeType: pendingFile.mimeType,
                categoryId: category.id
            )
        }
    }

    private func readPendingFile(from url: URL) -> PendingFileUpload? {
        PendingFileUpload.read(from: url)
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

#if os(macOS)
private struct MacTiledComposerBar: NSViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat

    let isSending: Bool
    let onImageData: (Data) -> Void
    let onFile: (PendingFileUpload) -> Void
    let onUnsupportedFile: (URL) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            height: $height,
            onImageData: onImageData,
            onFile: onFile,
            onUnsupportedFile: onUnsupportedFile,
            onSubmit: onSubmit
        )
    }

    func makeNSView(context: Context) -> MacTiledComposerHostView {
        let host = MacTiledComposerHostView()
        context.coordinator.host = host
        host.textView.delegate = context.coordinator
        host.textView.onPasteImage = onImageData
        host.textView.onPasteFile = onFile
        host.textView.onSubmit = onSubmit
        host.imageButton.target = context.coordinator
        host.imageButton.action = #selector(Coordinator.pickImages)
        host.fileButton.target = context.coordinator
        host.fileButton.action = #selector(Coordinator.pickAttachments)
        host.sendButton.target = context.coordinator
        host.sendButton.action = #selector(Coordinator.submit)
        host.update(text: text, isSending: isSending)
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }
        return host
    }

    func updateNSView(_ host: MacTiledComposerHostView, context: Context) {
        context.coordinator.onImageData = onImageData
        context.coordinator.onFile = onFile
        context.coordinator.onUnsupportedFile = onUnsupportedFile
        context.coordinator.onSubmit = onSubmit
        host.textView.onPasteImage = onImageData
        host.textView.onPasteFile = onFile
        host.textView.onSubmit = onSubmit
        host.update(text: text, isSending: isSending)
        DispatchQueue.main.async {
            context.coordinator.recalculateHeight()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        @Binding var height: CGFloat

        weak var host: MacTiledComposerHostView?
        var onImageData: (Data) -> Void
        var onFile: (PendingFileUpload) -> Void
        var onUnsupportedFile: (URL) -> Void
        var onSubmit: () -> Void

        init(
            text: Binding<String>,
            height: Binding<CGFloat>,
            onImageData: @escaping (Data) -> Void,
            onFile: @escaping (PendingFileUpload) -> Void,
            onUnsupportedFile: @escaping (URL) -> Void,
            onSubmit: @escaping () -> Void
        ) {
            _text = text
            _height = height
            self.onImageData = onImageData
            self.onFile = onFile
            self.onUnsupportedFile = onUnsupportedFile
            self.onSubmit = onSubmit
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            text = textView.string
            host?.setSendEnabled(!textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            recalculateHeight()
        }

        @objc func pickImages() {
            openPanel(contentTypes: [.image]) { [weak self] urls in
                guard let self else { return }
                for url in urls {
                    if let imageData = PendingFileUpload.imageData(from: url) {
                        onImageData(imageData)
                    } else {
                        onUnsupportedFile(url)
                    }
                }
            }
        }

        @objc func pickAttachments() {
            openPanel(contentTypes: Self.supportedAttachmentTypes) { [weak self] urls in
                guard let self else { return }
                for url in urls {
                    if let imageData = PendingFileUpload.imageData(from: url) {
                        onImageData(imageData)
                    } else if let file = PendingFileUpload.read(from: url) {
                        onFile(file)
                    } else {
                        onUnsupportedFile(url)
                    }
                }
            }
        }

        @objc func submit() {
            guard let host else { return }
            let nextText = host.textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !nextText.isEmpty else { return }
            text = nextText
            onSubmit()
            host.textView.string = ""
            text = ""
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let host,
                  let layoutManager = host.textView.layoutManager,
                  let textContainer = host.textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let font = host.textView.font ?? NSFont.preferredFont(forTextStyle: .body)
            let lineHeight = layoutManager.defaultLineHeight(for: font)
            var usedHeight = layoutManager.usedRect(for: textContainer).height
            if host.textView.string.isEmpty {
                usedHeight = lineHeight
            }

            let fieldHeight = max(34, min(104, ceil(usedHeight + 12)))
            if abs(height - fieldHeight) > 0.5 {
                height = fieldHeight
            }
            host.setInputHeight(fieldHeight)
        }

        private func openPanel(contentTypes: [UTType], completion: @escaping ([URL]) -> Void) {
            guard host?.isSending == false else { return }
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = true
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.resolvesAliases = true
            panel.allowedContentTypes = contentTypes
            guard panel.runModal() == .OK else { return }
            completion(panel.urls)
        }

        private static var supportedAttachmentTypes: [UTType] {
            [
                .image,
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
    }
}

private final class MacTiledComposerHostView: NSView {
    let imageButton = NSButton()
    let fileButton = NSButton()
    let sendButton = NSButton()
    let textFieldContainer = MacTiledComposerTextFieldView()
    let textView = PasteAwareMacTextView()

    private let stackView = NSStackView()
    private var inputHeightConstraint: NSLayoutConstraint?
    private(set) var isSending = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    func update(text: String, isSending: Bool) {
        self.isSending = isSending
        textView.isEditable = !isSending
        textView.isSelectable = !isSending
        imageButton.isEnabled = !isSending
        fileButton.isEnabled = !isSending
        setSendEnabled(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        if !textView.hasMarkedText(), textView.string != text {
            textView.string = text
        }
        textFieldContainer.placeholder.isHidden = !textView.string.isEmpty
        textFieldContainer.needsLayout = true
    }

    func setSendEnabled(_ enabled: Bool) {
        sendButton.isEnabled = enabled && !isSending
        sendButton.contentTintColor = sendButton.isEnabled ? NSColor.controlAccentColor : NSColor.disabledControlTextColor
    }

    func setInputHeight(_ height: CGFloat) {
        inputHeightConstraint?.constant = height
        textFieldContainer.needsLayout = true
        textView.needsLayout = true
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false

        configureIconButton(imageButton, symbolName: "photo.badge.plus")
        configureIconButton(fileButton, symbolName: "paperclip")
        configureIconButton(sendButton, symbolName: "arrow.up.circle.fill", pointSize: 28)

        textView.isRichText = false
        textView.drawsBackground = false
        textView.backgroundColor = .clear
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = NSSize(width: 0, height: 6)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.allowsUndo = true

        textFieldContainer.textView = textView
        textFieldContainer.addSubview(textView)

        stackView.orientation = .horizontal
        stackView.alignment = .centerY
        stackView.spacing = 10
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(imageButton)
        stackView.addArrangedSubview(fileButton)
        stackView.addArrangedSubview(textFieldContainer)
        stackView.addArrangedSubview(sendButton)
        addSubview(stackView)

        inputHeightConstraint = textFieldContainer.heightAnchor.constraint(equalToConstant: 34)
        inputHeightConstraint?.priority = .required

        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor),
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageButton.widthAnchor.constraint(equalToConstant: 24),
            imageButton.heightAnchor.constraint(equalToConstant: 34),
            fileButton.widthAnchor.constraint(equalToConstant: 22),
            fileButton.heightAnchor.constraint(equalToConstant: 34),
            sendButton.widthAnchor.constraint(equalToConstant: 30),
            sendButton.heightAnchor.constraint(equalToConstant: 34),
            textFieldContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            inputHeightConstraint
        ].compactMap { $0 })

        textFieldContainer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textFieldContainer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageButton.setContentHuggingPriority(.required, for: .horizontal)
        fileButton.setContentHuggingPriority(.required, for: .horizontal)
        sendButton.setContentHuggingPriority(.required, for: .horizontal)
        updateColors()
    }

    private func configureIconButton(_ button: NSButton, symbolName: String, pointSize: CGFloat = 18) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: nil
        )
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        button.contentTintColor = .labelColor
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateColors() {
        textFieldContainer.updateColors()
    }
}

private final class MacTiledComposerTextFieldView: NSView {
    weak var textView: PasteAwareMacTextView?
    let placeholder = NSTextField(labelWithString: NSLocalizedString("message_list.input_placeholder", bundle: .main, comment: ""))

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var acceptsFirstResponder: Bool { true }

    override func layout() {
        super.layout()
        let insetBounds = bounds.insetBy(dx: 12, dy: 0)
        textView?.frame = insetBounds
        textView?.textContainer?.containerSize = NSSize(
            width: max(1, insetBounds.width),
            height: CGFloat.greatestFiniteMagnitude
        )
        placeholder.frame = CGRect(
            x: 12,
            y: max(0, (bounds.height - placeholder.intrinsicContentSize.height) / 2),
            width: max(0, bounds.width - 24),
            height: placeholder.intrinsicContentSize.height
        )
    }

    override func mouseDown(with event: NSEvent) {
        guard let textView else { return }
        window?.makeFirstResponder(textView)
        textView.mouseDown(with: event)
    }

    func updateColors() {
        wantsLayer = true
        layer?.cornerRadius = 16
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.096, alpha: 1)
            }
            return NSColor(calibratedWhite: 0.992, alpha: 1)
        }.cgColor
        layer?.borderWidth = 1
        layer?.borderColor = NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 1.0, alpha: 0.13)
            }
            return NSColor(calibratedWhite: 0.0, alpha: 0.08)
        }.cgColor
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        placeholder.textColor = .secondaryLabelColor
        placeholder.font = NSFont.preferredFont(forTextStyle: .body)
        placeholder.lineBreakMode = .byTruncatingTail
        addSubview(placeholder)
        updateColors()
    }
}
#endif

private struct NewMessageCategorySheet: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    let onManageCategories: () -> Void

    @State private var name = ""
    @State private var color: MessageCategoryColor = .sky
    @State private var showDuplicateNameAlert = false
    #if os(iOS)
    @FocusState private var isNameFocused: Bool
    #endif

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

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isDuplicateCategoryName(_ name: String) -> Bool {
        syncManager.categories.contains { category in
            category.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func createCategory() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !isDuplicateCategoryName(trimmed) else {
            showDuplicateNameAlert = true
            return
        }

        Task {
            let _ = await syncManager.createCategory(name: trimmed, color: color)
            dismiss()
        }
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "message_category.name_placeholder", bundle: .main), text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit {
                            if canCreate {
                                createCategory()
                            }
                        }
                }

                Section("message_category.color_label") {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                        ForEach(MessageCategoryColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(colorAccent(option))
                                        .frame(width: 13, height: 13)

                                    Text(colorName(for: option))
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)

                                    Spacer(minLength: 0)

                                    if option == color {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(colorAccent(option))
                                    }
                                }
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 11)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(colorAccent(option).opacity(option == color ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(option == color ? colorAccent(option).opacity(0.55) : Color.clear, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }

                Section {
                    Button {
                        onManageCategories()
                    } label: {
                        HStack {
                            Label("message_list.manage_categories", systemImage: "slider.horizontal.3")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.syncaPageBackground)
            .navigationTitle("message_category.new_section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("message_category.add_action") {
                        createCategory()
                    }
                    .disabled(!canCreate)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                isNameFocused = true
            }
        }
        .alert("message_category.duplicate_title", isPresented: $showDuplicateNameAlert) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("message_category.duplicate_message")
        }
        #else
        VStack(spacing: 0) {
            HStack {
                Text("message_category.new_section", bundle: .main)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.primary)

                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                TextField(String(localized: "message_category.name_placeholder", bundle: .main), text: $name)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.syncaInputFieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.syncaInputFieldBorder, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    Text("message_category.color_label", bundle: .main)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                        ForEach(MessageCategoryColor.allCases) { option in
                            Button {
                                color = option
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(colorAccent(option))
                                        .frame(width: 12, height: 12)
                                    Text(colorName(for: option))
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(colorAccent(option).opacity(option == color ? 0.18 : 0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(option == color ? colorAccent(option).opacity(0.55) : Color.syncaCardBorder, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(22)

            Divider()

            HStack(spacing: 12) {
                Button {
                    onManageCategories()
                } label: {
                    Text("message_list.manage_categories", bundle: .main)
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

                Spacer()

                Button("common.cancel") { dismiss() }

                Button("message_category.add_action") {
                    createCategory()
                }
                .disabled(!canCreate)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 16)
        }
        .alert("message_category.duplicate_title", isPresented: $showDuplicateNameAlert) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("message_category.duplicate_message")
        }
        .frame(minWidth: 420, idealWidth: 440, minHeight: 300, idealHeight: 330)
        #endif
    }
}

private struct CategoryDraftRow: Identifiable, Equatable {
    let localId: String
    let categoryId: String?
    var name: String
    var color: MessageCategoryColor

    var id: String { localId }
}

private struct CategoryValidationAlert: Identifiable {
    let id = UUID()
    let titleKey: String
    let messageKey: String
}

private struct MessageCategoryManagerSheet: View {
    @EnvironmentObject var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss

    @State private var draftRows: [CategoryDraftRow] = []
    @State private var pendingDeleteRow: CategoryDraftRow?
    @State private var validationAlert: CategoryValidationAlert?
    @State private var focusedRowId: String?

    private var editableCategories: [SyncaMessageCategory] {
        syncManager.categories.filter { !$0.isDefault }
    }

    private func reloadDraftRows() {
        draftRows = editableCategories.map { category in
            CategoryDraftRow(
                localId: category.id,
                categoryId: category.id,
                name: category.name,
                color: category.color
            )
        }
    }

    private func addDraftRow() {
        let newId = "new-\(UUID().uuidString)"
        draftRows.append(
            CategoryDraftRow(
                localId: newId,
                categoryId: nil,
                name: "",
                color: .sky
            )
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            focusedRowId = newId
        }
    }

    private func deleteDraftRow(_ row: CategoryDraftRow) {
        draftRows.removeAll { $0.localId == row.localId }
    }

    private func moveDraftRow(from sourceIndex: Int, to destinationIndex: Int) {
        guard draftRows.indices.contains(sourceIndex),
              draftRows.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        let row = draftRows.remove(at: sourceIndex)
        draftRows.insert(row, at: destinationIndex)
    }

    private func validateDraftRows() -> Bool {
        let names = draftRows.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }
        if names.contains(where: \.isEmpty) {
            validationAlert = CategoryValidationAlert(
                titleKey: "message_category.invalid_title",
                messageKey: "message_category.invalid_message"
            )
            return false
        }

        var seenNames = Set<String>()
        for name in names {
            let key = name.localizedLowercase
            if seenNames.contains(key) {
                validationAlert = CategoryValidationAlert(
                    titleKey: "message_category.duplicate_title",
                    messageKey: "message_category.duplicate_message"
                )
                return false
            }
            seenNames.insert(key)
        }

        return true
    }

    private func saveDraftRows() {
        guard validateDraftRows() else { return }

        let rows = draftRows
        let originalCategories = editableCategories
        let originalById = Dictionary(uniqueKeysWithValues: originalCategories.map { ($0.id, $0) })
        let keptIds = Set(rows.compactMap(\.categoryId))

        Task {
            for category in originalCategories where !keptIds.contains(category.id) {
                await syncManager.deleteCategory(id: category.id)
            }

            var orderedCategoryIds: [String] = []
            for row in rows {
                let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let categoryId = row.categoryId {
                    guard let original = originalById[categoryId] else { continue }
                    let updatedName = name == original.name ? nil : name
                    let updatedColor = row.color == original.color ? nil : row.color
                    if updatedName != nil || updatedColor != nil {
                        await syncManager.updateCategory(id: categoryId, name: updatedName, color: updatedColor)
                    }
                    orderedCategoryIds.append(categoryId)
                } else {
                    if let category = await syncManager.createCategory(name: name, color: row.color) {
                        orderedCategoryIds.append(category.id)
                    }
                }
            }

            await syncManager.reorderCategories(ids: orderedCategoryIds)
            dismiss()
        }
    }

    var body: some View {
        Group {
            #if os(iOS)
            iosBody
            #else
            macOSBody
            #endif
        }
        .onAppear {
            reloadDraftRows()
            #if os(macOS)
            DispatchQueue.main.async {
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
            #endif
        }
        .alert("message_category.delete_confirm_title", isPresented: Binding(
            get: { pendingDeleteRow != nil },
            set: { if !$0 { pendingDeleteRow = nil } }
        )) {
            Button("common.cancel", role: .cancel) {
                pendingDeleteRow = nil
            }
            Button("common.delete", role: .destructive) {
                if let pendingDeleteRow {
                    deleteDraftRow(pendingDeleteRow)
                }
                pendingDeleteRow = nil
            }
        } message: {
            Text("message_category.delete_confirm_message")
        }
        .alert(item: $validationAlert) { alert in
            Alert(
                title: Text(LocalizedStringKey(alert.titleKey)),
                message: Text(LocalizedStringKey(alert.messageKey)),
                dismissButton: .default(Text("common.ok"))
            )
        }
        #if os(macOS)
        .frame(minWidth: 560, idealWidth: 600, minHeight: 380, idealHeight: 460)
        #endif
    }

    #if os(iOS)
    private var iosBody: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(draftRows.indices, id: \.self) { index in
                        CategoryDraftListRow(
                            row: $draftRows[index],
                            canMoveUp: index > 0,
                            canMoveDown: index < draftRows.count - 1,
                            onMoveUp: { moveDraftRow(from: index, to: index - 1) },
                            onMoveDown: { moveDraftRow(from: index, to: index + 1) },
                            onDelete: { pendingDeleteRow = draftRows[index] },
                            focusedRowId: $focusedRowId
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 12))
                    }
                }

                Section {
                    Button {
                        addDraftRow()
                    } label: {
                        Label("message_category.add_action", systemImage: "plus")
                            .font(.body.weight(.semibold))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.syncaPageBackground)
            .navigationTitle("message_category.section_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.save") { saveDraftRows() }
                        .fontWeight(.semibold)
                }
            }
        }
    }
    #else
    private var macOSBody: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(draftRows.indices, id: \.self) { index in
                            CategoryDraftListRow(
                                row: $draftRows[index],
                                canMoveUp: index > 0,
                                canMoveDown: index < draftRows.count - 1,
                                onMoveUp: { moveDraftRow(from: index, to: index - 1) },
                                onMoveDown: { moveDraftRow(from: index, to: index + 1) },
                                onDelete: { pendingDeleteRow = draftRows[index] },
                                focusedRowId: $focusedRowId
                            )
                        }

                        Button {
                            addDraftRow()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "plus")
                                Text("message_category.add_action", bundle: .main)
                            }
                            .font(.callout.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(.primary)
                            .background(Color.syncaCardBackground.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(Color.syncaCardBorder, style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                }
                .background(Color.syncaPageBackground.opacity(0.55))

                Divider()

                HStack {
                    Button("common.cancel") { dismiss() }
                    Spacer()
                    Button("common.save") { saveDraftRows() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .navigationTitle("message_category.section_title")
        }
    }
    #endif
}

private struct CategoryDraftListRow: View {
    @Binding var row: CategoryDraftRow
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void
    @Binding var focusedRowId: String?

    @State private var showColorPicker = false
    @FocusState private var isFocused: Bool

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

    @ViewBuilder
    private func colorLabel(for color: MessageCategoryColor) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(colorAccent(color))
                .frame(width: 10, height: 10)
            Text(colorName(for: color))
        }
    }

    private var colorPickerButton: some View {
        Button {
            showColorPicker.toggle()
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(colorAccent(row.color))
                    .frame(width: 11, height: 11)
                Text(colorName(for: row.color))
                    .font(.callout.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 120, alignment: .leading)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(colorAccent(row.color).opacity(0.14), in: Capsule())
            .overlay(
                Capsule()
                    .stroke(colorAccent(row.color).opacity(0.34), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        #if os(iOS)
        .sheet(isPresented: $showColorPicker) {
            NavigationStack {
                ScrollView {
                    colorPickerContent
                        .padding(16)
                }
                .navigationTitle(Text("message_category.color_label", bundle: .main))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { showColorPicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        #else
        .popover(isPresented: $showColorPicker, arrowEdge: .bottom) {
            colorPickerContent
                .padding(8)
                .frame(width: 180)
        }
        #endif
    }

    private var colorPickerContent: some View {
        #if os(iOS)
        let verticalPadding: CGFloat = 10
        let fontSize: Font = .body.weight(.medium)
        let spacing: CGFloat = 4
        let circleSize: CGFloat = 16
        #else
        let verticalPadding: CGFloat = 8
        let fontSize: Font = .callout.weight(.semibold)
        let spacing: CGFloat = 6
        let circleSize: CGFloat = 11
        #endif

        return VStack(alignment: .leading, spacing: spacing) {
            ForEach(MessageCategoryColor.allCases) { color in
                Button {
                    row.color = color
                    showColorPicker = false
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(colorAccent(color))
                            .frame(width: circleSize, height: circleSize)

                        Text(colorName(for: color))
                            .font(fontSize)

                        Spacer(minLength: 16)

                        if color == row.color {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(colorAccent(color))
                        }
                    }
                    .contentShape(Rectangle())
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, verticalPadding)
                    .background(color == row.color ? colorAccent(color).opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var moveControls: some View {
        VStack(spacing: 2) {
            Button(action: onMoveUp) {
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 18)
            }
            .disabled(!canMoveUp)
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("message_category.move_up", bundle: .main))

            Button(action: onMoveDown) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
                    .frame(width: 24, height: 18)
            }
            .disabled(!canMoveDown)
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("message_category.move_down", bundle: .main))
        }
        .foregroundStyle(.secondary)
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "trash")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.red.opacity(0.6))
                .frame(width: 30, height: 30)
                .background(Color.red.opacity(0.10), in: Circle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("message_category.delete_action", bundle: .main))
    }

    var body: some View {
        #if os(iOS)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(colorAccent(row.color))
                .frame(width: 4, height: 32)

            TextField(String(localized: "message_category.name_placeholder", bundle: .main), text: $row.name)
                .textFieldStyle(.plain)
                .font(.body)
                .textInputAutocapitalization(.words)
                .focused($isFocused)
                .onChange(of: focusedRowId) { newId in
                    if newId == row.localId {
                        isFocused = true
                        focusedRowId = nil
                    }
                }

            Spacer(minLength: 8)

            colorPickerButton
            deleteButton
            moveControls
        }
        .padding(.vertical, 8)
        #else
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 999)
                .fill(colorAccent(row.color))
                .frame(width: 5)
                .padding(.vertical, 3)

            TextField(String(localized: "message_category.name_placeholder", bundle: .main), text: $row.name)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onChange(of: focusedRowId) { newId in
                    if newId == row.localId {
                        isFocused = true
                        focusedRowId = nil
                    }
                }

            Spacer(minLength: 8)

            colorPickerButton
            deleteButton
            moveControls
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.syncaCardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.syncaCardBorder, lineWidth: 1)
        )
        #endif
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
