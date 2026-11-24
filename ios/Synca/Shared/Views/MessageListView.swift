import SwiftUI
import PhotosUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import UniformTypeIdentifiers

struct SyncStatusToastView: View {
    let status: SyncManager.SyncStatus
    var topInset: CGFloat? = nil

    var body: some View {
        Group {
            switch status {
            case .success:
                successLabel(Text("message_list.sync_success", bundle: .main))
            case .successMessage(let message):
                successLabel(Text(message))
            case .progress(let message):
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                    Text(message)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .modifier(StatusToastStyle(backgroundColor: Color.accentColor, topInset: resolvedTopInset))
            case .error(let message):
                Label {
                    Text(message)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                } icon: {
                    Image(systemName: "xmark.circle.fill")
                }
                .modifier(StatusToastStyle(backgroundColor: .red, topInset: resolvedTopInset))
            case .idle, .syncing:
                EmptyView()
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: status)
    }

    private var resolvedTopInset: CGFloat {
        if let topInset { return topInset }
        #if os(iOS)
        return 58
        #else
        return 16
        #endif
    }

    private func successLabel(_ text: Text) -> some View {
        Label {
            text
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .modifier(StatusToastStyle(backgroundColor: .green, topInset: resolvedTopInset))
    }
}

private struct StatusToastStyle: ViewModifier {
    let backgroundColor: Color
    let topInset: CGFloat

    func body(content: Content) -> some View {
        content
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(backgroundColor)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            .padding(.top, topInset)
    }
}

struct MessageListView: View {
    #if os(iOS)
    @State private var hasInitializedWorkspace = false
    #endif
    @State private var categorySwipeIsHorizontal: Bool?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @State private var feedViewport = FeedViewportReference()
    @ScaledMetric(relativeTo: .caption) private var categoryBadgeDiameter: CGFloat = 22
    @State private var drawerOpen = false
    @State private var drawerTranslation: CGFloat = 0
    @State private var drawerWidth: CGFloat = 324
    @GestureState private var drawerGestureActive = false
    @State private var showIOSSettings = false
    private var phoneLayout: Bool { horizontalSize == .compact }
    #endif
    private enum Timing {
        static let scrollCoalescingNanoseconds: UInt64 = 50_000_000
        static let errorDisplayNanoseconds: UInt64 = 6_000_000_000
    }

    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var api: APIClient
    @EnvironmentObject var accessManager: AccessManager
    @EnvironmentObject var purchaseManager: PurchaseManager
    @ObservedObject private var settings = SettingsManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSearch = false
    @State private var searchQuery = ""
    @State private var searchAnchorY: CGFloat?
    @State private var searchRowHeight: CGFloat = 0
    @State private var completionScrollTask: Task<Void, Never>?
    @State private var viewportInteractionRevision = 0
    @State private var completionBottomSpace: CGFloat = 0
    @State private var visibleRecordFrames: [String: CGRect] = [:]
    @State private var searchRowFrame: CGRect?
    @State private var searchPositionedTextAnchor = false
    @State private var searchViewportHeight: CGFloat = 0
    @State private var searchMatchedText: String?
    @State private var searchTarget: String?
    @State private var searchTargetCategory: String?
    @State private var searchPositionRevision = 0
    @State private var searchImageRevision = 0
    @State private var searchHighlight: String?
    @State private var searchScrollSuppressed = false
    @State private var searchPresentationSuppressesScroll = false
    @State private var scrollTask: Task<Void, Never>?
    @State private var expandedTextIDs: Set<String> = []
    @State private var textLayoutRevision = 0
    @State private var collapsedRowTarget: (category: String?, row: String)?
    @State private var inputText = ""
    @State private var composerFocusRequest = 0
    @FocusState private var sidebarCategoryFocus: String?
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showFileImporter = false
    @State private var showLogoutConfirm = false
    @State private var showClearAllConfirm = false
    @State private var showAboutInfo = false
    @State private var showAccountInfo = false
    @State private var showFeedbackComposer = false
    @State private var showSessionExpired = false
    @State private var inputHeight: CGFloat = 40
    @State private var editingMessage: SyncaMessage?
    @State private var selectedImageMessage: SyncaMessage? // #NEW: Centralized gallery state
    @State private var shouldScrollToBottomAfterSend = false
    @State private var postSendScrollWindowID = UUID()
    @State private var shouldScrollToBottomAfterInitialLoad = false
    @State private var initialLoadScrollWindowID = UUID()
    @State private var showFeedbackSuccessToast = false
    @State private var showCreateCategory = false
    @State private var showCategoryManager = false
    @State private var sidebarDragPayload: String?
    @State private var sidebarReordering = false
    @State private var sidebarEditTarget: SyncaMessageCategory?
    @State private var sidebarDeleteTarget: SyncaMessageCategory?
    #if os(macOS)
    @AppStorage("synca.sidebarWidth") private var preferredSidebarWidth = 220.0
    @State private var sidebarLiveWidth: CGFloat?
    @State private var sidebarResizeStart: CGFloat?
    @State private var desktopAvailableWidth: CGFloat = 800
    @State private var sidebarResizeHovered = false
    private var sidebarMaximumWidth: CGFloat { max(200, min(360, desktopAvailableWidth - 480)) }
    private var desktopSidebarWidth: CGFloat {
        min(sidebarMaximumWidth, max(200, sidebarLiveWidth ?? (preferredSidebarWidth.isFinite ? preferredSidebarWidth : 220)))
    }
    #endif
    @State private var showAppSettings = false
    @State private var showManagementMenu = false
    @State private var showAIConnection = false
    @State private var categoryToEdit: SyncaMessageCategory?
    @State private var accountEntryHeight: CGFloat = 112
    @FocusState private var managementMenuFocused: Bool

    private var workspaceNavigation: some View {
        MessageListNavigationContainer {
            rootContent
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 4) {
                if let progress = syncManager.uploadProgress {
                    HStack(spacing: 12) {
                        ProgressView(value: progress).accessibilityLabel(Text("storage.uploading"))
                        Text(progress, format: .percent.precision(.fractionLength(0))).monospacedDigit()
                        Button("common.cancel") { syncManager.cancelFileUpload() }
                    }.padding().background(.regularMaterial)
                } else if syncManager.failedFile != nil {
                    HStack {
                        Text("storage.retry_hint").font(.caption)
                        Spacer()
                        Button("storage.retry") { Task { await syncManager.retryFileUpload() } }
                        Button("common.cancel") { syncManager.failedFile = nil }
                    }.padding().background(.regularMaterial)
                }
            }
            }
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
            #if os(iOS)
            .fullScreenCover(isPresented: $showSearch, onDismiss: finishSearchPresentation) { searchSheet }
            #else
            .sheet(isPresented: $showSearch, onDismiss: finishSearchPresentation) { searchSheet }
            #endif
            .sheet(isPresented: $showAccountInfo) {
                AccountSheet(
                    accountEmail: api.currentUserEmail,
                    onDeleteAccount: { try await api.deleteAccount() },
                    onLogout: {
                        syncManager.reset()
                        AuthService.shared.signOut()
                    }
                ).syncaPreferences()
            }
            .sheet(isPresented: $showAIConnection) { AIConnectionView().syncaPreferences() }
            .sheet(isPresented: $showAppSettings) {
                AppSettingsView()
                #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                #endif
            }
            .sheet(isPresented: $showAboutInfo) {
                AboutSyncaSheet().syncaPreferences()
            }
            #if os(iOS)
            .fullScreenCover(isPresented: $showCategoryManager) {
                MessageCategoryManagerSheet().environmentObject(syncManager).syncaPreferences()
            }
            #else
            .sheet(isPresented: $showCategoryManager) {
                MessageCategoryManagerSheet().environmentObject(syncManager).syncaPreferences()
            }
            #endif
            #if os(macOS)
            .sheet(item: $sidebarEditTarget) { category in
                NewMessageCategorySheet(category: category) {
                    sidebarEditTarget = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        showCategoryManager = true
                    }
                }
                .environmentObject(syncManager)
                .syncaPreferences()
            }
            #endif
            .sheet(isPresented: $showCreateCategory) {
                NewMessageCategorySheet(category: categoryToEdit) {
                    showCreateCategory = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        showCategoryManager = true
                    }
                }
                    .environmentObject(syncManager)
                    .syncaPreferences()
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
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
    }

    var body: some View {
        workspaceNavigation
        #if os(iOS)
        .accessibilityHidden(drawerOpen)
        .allowsHitTesting(!drawerOpen)
        .overlay(alignment: .leading) { if phoneLayout { phoneDrawer.accessibilityHidden(!drawerOpen) } }
        .onChange(of: drawerGestureActive) { active in
            guard !active else { return }
            // A cancelled drag has no onEnded. Restore the resting position, too.
            DispatchQueue.main.async {
                guard !drawerGestureActive else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { drawerTranslation = 0 }
                categorySwipeIsHorizontal = nil
            }
        }
        .onChange(of: horizontalSize) { _ in drawerOpen = false; drawerTranslation = 0 }
        .fullScreenCover(isPresented: Binding(get: { showIOSSettings && phoneLayout }, set: { showIOSSettings = $0 })) {
            iosSettings
        }
        .sheet(isPresented: Binding(get: { showIOSSettings && !phoneLayout }, set: { showIOSSettings = $0 })) {
            iosSettings.presentationDetents([.large])
        }
        #endif
        .onChange(of: api.currentUserEmail) { _ in searchQuery = ""; showSearch = false }
        .overlay(alignment: .top) { syncStatusOverlay }
        .overlay(alignment: .top) { feedbackToastOverlay }
        .overlay { loadingOverlay }
        .task(id: searchHighlight) {
            guard let id = searchHighlight else { return }
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled, searchHighlight == id else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.4)) { searchHighlight = nil }
        }
        .onChange(of: accessManager.showAccessCenter) { requested in
            if requested {
                accessManager.showAccessCenter = false
                showAccountInfo = true
            }
        }
        .sheet(item: $editingMessage) { message in
            MessageTextEditorView(message: message).syncaPreferences()
        }
        .sheet(isPresented: $showFeedbackComposer) {
            FeedbackComposerView()
                .environmentObject(api)
                .syncaPreferences()
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
            #if os(iOS)
            guard !hasInitializedWorkspace else { return }
            #endif
            let isReturningFromSearch = searchPresentationSuppressesScroll
            shouldScrollToBottomAfterInitialLoad = !isReturningFromSearch
            await syncManager.restoreCachedDataIfAvailable()
            
            let pm = purchaseManager
            Task.detached(priority: .background) {
                await PushTokenManager.shared.uploadCachedTokenIfPossible()
                await pm.loadProducts()
                _ = try? await pm.syncLatestTransactions()
            }
            
            await syncManager.fullSync(manual: true, showSuccessStatus: false)
            if !isReturningFromSearch, !syncManager.orderedMessages.isEmpty {
                beginInitialLoadScrollWindow()
            }
            guard !Task.isCancelled else { return }
            #if os(iOS)
            // Initial loading can finish after all windows entered the background.
            if UIApplication.shared.applicationState != .background { syncManager.startPolling() }
            #else
            syncManager.startPolling()
            #endif
            self.updateBadge()
            #if os(iOS)
            hasInitializedWorkspace = true
            #endif
        }
        #if os(iOS)
        .onChange(of: syncManager.selectedCategoryId) { category in
            collapsedRowTarget = nil
            // The destination row can expand before this category callback runs.
            // Preserve that search target instead of collapsing it underneath
            // the in-flight jump and forcing a second expansion/layout pass.
            if category == searchTargetCategory, let target = searchTarget {
                expandedTextIDs.formIntersection([target])
            } else {
                expandedTextIDs.removeAll()
            }
        }
        #endif
        .onChange(of: syncManager.selectedCategoryId) { category in
            if category != searchTargetCategory {
                interruptSearchPositioning()
                searchScrollSuppressed = false
            }
        }
        .onChange(of: inputText) { _ in
            interruptSearchPositioning()
        }
        .onChange(of: syncManager.isSending) { sending in
            if sending { searchScrollSuppressed = false; searchTarget = nil }
        }
        .onChange(of: syncManager.unclearedCount) { _ in
            self.updateBadge()
        }
        .onChange(of: syncManager.sessionExpired) { expired in
            if expired {
                showSessionExpired = true
            }
        }
        .task(id: syncManager.errorMessage) {
            guard let message = syncManager.errorMessage else { return }
            #if os(iOS)
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            UIAccessibility.post(notification: .announcement, argument: message)
            #elseif os(macOS)
            NSAccessibility.post(
                element: NSApp.mainWindow as Any? ?? NSApp as Any,
                notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue]
            )
            #endif
            try? await Task.sleep(nanoseconds: Timing.errorDisplayNanoseconds)
            guard !Task.isCancelled, syncManager.errorMessage == message else { return }
            syncManager.errorMessage = nil
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            syncManager.startPolling()
        }
        #endif
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

    private var searchButton: some View {
        Button {
            scrollTask?.cancel()
            searchTarget = nil
            searchHighlight = nil
            // A full-screen presentation can recreate the iOS reader on dismissal.
            // Preserve its offset instead of running initial-load bottom scrolling.
            searchPresentationSuppressesScroll = true
            shouldScrollToBottomAfterInitialLoad = false
            shouldScrollToBottomAfterSend = false
            #if os(iOS)
            searchQuery = ""
            #endif
            showSearch = true
        } label: {
            Image(systemName: "magnifyingglass")
                #if os(macOS)
                .frame(width: 44, height: 44).contentShape(Rectangle())
                #endif
        }
            .accessibilityLabel(Text("search.title"))
            .accessibilityIdentifier("search-open")
            .help(Text("search.title"))
            #if os(macOS)
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            #endif
    }

    #if os(iOS)
    private var iosSettings: some View {
        IOSSettingsView(onClose: { showIOSSettings = false },
            onDeleteAccount: { try await api.deleteAccount() },
            onLogout: {
                syncManager.reset()
                AuthService.shared.signOut()
            })
    }
    #endif

    private func finishSearchPresentation() {
        // Presentation suppression ends after the returning reader's appearance.
        // Result navigation owns its independent suppression; cancellation restores
        // exactly the remote-append behavior that existed before opening search.
        searchPresentationSuppressesScroll = false
    }

    private var searchSheet: some View {
        MessageSearchView(currentCategoryID: selectedFilterCategoryId, query: $searchQuery, onSelect: selectSearchResult)
            .environmentObject(syncManager).syncaPreferences()
    }

    private func selectSearchResult(_ result: MessageSearchResult) -> Bool {
        let id = result.id
        guard let message = syncManager.messages.first(where: { $0.id == id && !$0.isDeleted }) else { return false }
        let category = message.categoryId.flatMap { id in syncManager.categories.first(where: { $0.id == id })?.id }
        scrollTask?.cancel()
        shouldScrollToBottomAfterSend = false
        shouldScrollToBottomAfterInitialLoad = false
        initialLoadScrollWindowID = UUID()
        postSendScrollWindowID = UUID()
        collapsedRowTarget = nil
        searchScrollSuppressed = true
        searchAnchorY = nil
        searchRowHeight = 0
        searchRowFrame = nil
        searchPositionedTextAnchor = false
        searchTarget = id
        searchMatchedText = result.matchedText
        searchHighlight = nil
        searchTargetCategory = category ?? syncManager.allCategoryPseudoId
        showSearch = false
        syncManager.selectCategory(searchTargetCategory)
        searchPositionRevision += 1
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        #endif
        return true
    }

    private func interruptSearchPositioning() {
        guard searchTarget != nil else { return }
        searchTarget = nil
        searchHighlight = nil
        // Keep remote append/image callbacks from immediately taking the viewport back.
        scrollTask?.cancel()
        shouldScrollToBottomAfterInitialLoad = false
        shouldScrollToBottomAfterSend = false
    }

    private var rootContent: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            desktopSidebar
            Divider()
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedCategoryTitle).font(.title2.weight(.semibold))
                        (Text(String(format: String(syncaLocalized: "message_list.pending_count"), todoCount(for: selectedFilterCategoryId)))
                            + Text(" · ")
                            + Text(String(format: String(syncaLocalized: "message_list.completed_count"), filteredMessages.filter { $0.isCleared }.count)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        searchButton
                        refreshButton.help(Text("message_list.sync"))
                        clearAllButton.help(Text("message_list.clear_completed"))
                    }
                }
                .padding(.horizontal, 28).padding(.vertical, 18)
                .background(MacWindowDragArea())
                .frame(maxWidth: .infinity)
                desktopContentDivider
                singleMessageContent
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(GeometryReader { proxy in
            Color.clear.onAppear { desktopAvailableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { desktopAvailableWidth = $0 }
        })
        .ignoresSafeArea(.container, edges: .top)
        .overlay {
            if showManagementMenu {
                Color.clear.contentShape(Rectangle()).onTapGesture { showManagementMenu = false }
                    .accessibilityLabel(Text("common.cancel"))
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showManagementMenu {
                VStack(alignment: .leading, spacing: 2) { managementMenuItems }
                    .buttonStyle(ManagementMenuRowStyle())
                    .padding(8).frame(width: desktopSidebarWidth - 24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.syncaCardBorder, lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    .padding(.leading, 12).padding(.bottom, accountEntryHeight + 22)
                    .onAppear { DispatchQueue.main.async { managementMenuFocused = true } }
                    .onExitCommand { showManagementMenu = false }
                    .syncaPreferences()
            }
        }
        #else
        VStack(spacing: 0) {
            if !phoneLayout {
                if let status = accessManager.status {
                    DailyQuotaView(status: status).padding(.horizontal, 20).padding(.top, 6)
                }
                categoryToolbar
            }
            singleMessageContent
        }
        #endif
    }

    private var singleMessageContent: some View {
        VStack(spacing: 0) {
            messageList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                #if os(iOS)
                .simultaneousGesture(phoneLayout && syncManager.hasCompletedInitialLoad && !filteredMessages.isEmpty ? nil : DragGesture(minimumDistance: 12)
                    .updating($drawerGestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        if categorySwipeIsHorizontal == nil {
                            categorySwipeIsHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                        }
                        guard phoneLayout, categorySwipeIsHorizontal == true,
                              value.startLocation.x < 32, value.translation.width > 0 else { return }
                        drawerTranslation = min(drawerWidth, value.translation.width)
                    }
                    .onEnded { value in
                        defer { categorySwipeIsHorizontal = nil }
                        guard categorySwipeIsHorizontal == true else { return }
                        if phoneLayout {
                            guard value.startLocation.x < 32 else { return }
                            toggleDrawer(value.predictedEndTranslation.width > drawerWidth * 0.4)
                        } else {
                            switchCategory(horizontal: value.translation.width, vertical: 0)
                        }
                    })
                .accessibilityAction(named: Text("message_list.next_category")) { switchCategory(horizontal: -80, vertical: 0) }
                .accessibilityAction(named: Text("message_list.previous_category")) { switchCategory(horizontal: 80, vertical: 0) }
                #endif
            inputBar.frame(maxWidth: streamMaximumWidth + 40)
        }
    }

    #if os(macOS)
    // The header spans the detail pane; records and composer keep their own width limits.
    private var desktopContentDivider: some View {
        Divider()
            .frame(maxWidth: .infinity)
    }
    #endif

    private var selectedCategoryTitle: String {
        guard let category = syncManager.categories.first(where: { $0.id == selectedFilterCategoryId }) else {
            return String(syncaLocalized: "message_list.all_records")
        }
        return category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name
    }

    #if os(macOS)
    private var desktopSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("LoginLogo").resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 8))
                Text("Synca").font(.title2.weight(.semibold))
            }.padding(.horizontal, 24).padding(.top, 48).padding(.bottom, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MacWindowDragArea())
            MacSidebarScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarCategory(id: syncManager.allCategoryPseudoId, title: String(syncaLocalized: "message_list.all_records"), color: nil, count: allTodoCount)
                        .padding(.bottom, 16)
                    CategoryReorderStack(categories: syncManager.categories, spacing: 4, handleOnly: false, disabled: sidebarReordering, onCommit: { ids in
                        sidebarReordering = true
                        _ = await syncManager.reorderCategories(ids: ids)
                        sidebarReordering = false
                    }) { category in
                        sidebarCategory(id: category.id, title: category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name, color: categoryDisplayColor(category.color, hex: category.colorHex), count: todoCount(for: category.id))
                            .contextMenu {
                                Button("message_category.modify") { sidebarEditTarget = category }
                                    .disabled(sidebarReordering)
                                Button("message_category.move_up") { moveSidebar(category, by: -1) }
                                    .disabled(sidebarReordering || !canMoveSidebar(category, by: -1))
                                Button("message_category.move_down") { moveSidebar(category, by: 1) }
                                    .disabled(sidebarReordering || !canMoveSidebar(category, by: 1))
                                Divider()
                                Button("common.delete") { sidebarDeleteTarget = category }
                                    .disabled(category.isDefault || sidebarReordering)
                            }
                            .accessibilityAction(named: Text("message_category.move_up")) { moveSidebar(category, by: -1) }
                            .accessibilityAction(named: Text("message_category.move_down")) { moveSidebar(category, by: 1) }
                    }
                    Button { categoryToEdit = nil; showCreateCategory = true } label: {
                        Label("message_category.add_action", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
            }
            Spacer(minLength: 12)
            Button { showManagementMenu.toggle() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16)).frame(width: 16).foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                        Text(api.currentUserEmail ?? String(syncaLocalized: "account.section_title"))
                            .font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            .help(api.currentUserEmail ?? String(syncaLocalized: "account.section_title"))
                            if let status = accessManager.status {
                                Text(planName(status)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let status = accessManager.status { DailyQuotaView(status: status) }
                }
                .padding(12).background(Color.syncaCardBackground, in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain).fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { accountEntryHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { accountEntryHeight = $0 }
            })
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("account.menu"))
            .accessibilityValue(Text(accountAccessibilityValue))
            .accessibilityAddTraits(.isButton)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)
        }
        .alert("message_category.delete_confirm_title", isPresented: Binding(get: { sidebarDeleteTarget != nil }, set: { if !$0 { sidebarDeleteTarget = nil } })) {
            Button("common.cancel", role: .cancel) { sidebarDeleteTarget = nil }
            Button("common.delete", role: .destructive) {
                guard let category = sidebarDeleteTarget, !category.isDefault, !sidebarReordering else { return }
                sidebarDeleteTarget = nil
                sidebarReordering = true
                Task { @MainActor in
                    _ = await syncManager.deleteCategory(id: category.id)
                    sidebarReordering = false
                }
            }
        } message: {
            if let category = sidebarDeleteTarget,
               syncManager.messages.contains(where: { !$0.isDeleted && $0.categoryId == category.id }) {
                Text("message_category.delete_confirm_message")
            }
        }
        .frame(width: desktopSidebarWidth)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .trailing) {
            MacSidebarResizeHandle(
                onBegin: { sidebarResizeStart = desktopSidebarWidth },
                onDrag: { delta in
                    sidebarLiveWidth = min(sidebarMaximumWidth, max(200, (sidebarResizeStart ?? desktopSidebarWidth) + delta))
                },
                onEnd: {
                    preferredSidebarWidth = desktopSidebarWidth
                    sidebarLiveWidth = nil; sidebarResizeStart = nil
                },
                onReset: { preferredSidebarWidth = 220; sidebarLiveWidth = nil; sidebarResizeStart = nil },
                onHover: { sidebarResizeHovered = $0 }
            ).frame(width: 8)
                .overlay(alignment: .trailing) {
                    Rectangle().fill(Color.secondary.opacity(sidebarResizeHovered || sidebarResizeStart != nil ? 0.45 : 0)).frame(width: 2)
                        .allowsHitTesting(false)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("navigation.resize_sidebar"))
                .accessibilityValue(Text("\(Int(desktopSidebarWidth))"))
                .accessibilityAdjustableAction { direction in
                    let change: CGFloat = direction == .increment ? 10 : -10
                    preferredSidebarWidth = min(sidebarMaximumWidth, max(200, desktopSidebarWidth + change))
                }
        }
    }

    private func sidebarCategory(id: String, title: String, color: Color?, count: Int) -> some View {
        let selected = syncManager.selectedCategoryId == id
        return Button {
            syncManager.selectCategory(id)
            if NSApp.currentEvent?.clickCount == 2,
               let category = syncManager.categories.first(where: { $0.id == id }) {
                sidebarEditTarget = category
            } else {
                composerFocusRequest += 1
            }
        } label: {
            HStack(spacing: 10) {
                if id == syncManager.allCategoryPseudoId {
                    Image(systemName: "square.grid.2x2").frame(width: 16).accessibilityHidden(true)
                }
                Text(title).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if count > 0 { Text(count, format: .number).font(.caption2.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((color ?? (selected ? Color.syncaPageBackground : Color.primary)).opacity(selected ? 0.24 : 0.12), in: Capsule()) }
            }
            .padding(.leading, color == nil ? 12 : 20).padding(.trailing, 12)
            .padding(.vertical, 8).frame(minHeight: 44)
            .foregroundStyle(color == nil && selected ? Color.syncaPageBackground : Color.primary)
            .background(color == nil ? Color.primary.opacity(selected ? 1 : 0.06) : color!.opacity(selected ? 0.22 : 0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay { if color == nil && !selected { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.1), lineWidth: 1) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            .focused($sidebarCategoryFocus, equals: id)
            .keyboardShortcut(sidebarCategoryFocus == id ? KeyboardShortcut(.return, modifiers: []) : nil)
            .onMoveCommand { direction in
                let order = [syncManager.allCategoryPseudoId] + syncManager.categories.map(\.id)
                guard let index = order.firstIndex(of: id) else { return }
                let step: Int
                switch direction {
                case .up, .left: step = -1
                case .down, .right: step = 1
                default: return
                }
                let next = order[max(0, min(order.count - 1, index + step))]
                syncManager.selectCategory(next)
                sidebarCategoryFocus = next
            }
    }

    private func canMoveSidebar(_ category: SyncaMessageCategory, by offset: Int) -> Bool {
        let custom = syncManager.categories.filter { !$0.isDefault }
        guard !category.isDefault, let index = custom.firstIndex(where: { $0.id == category.id }) else { return false }
        return custom.indices.contains(index + offset)
    }

    private func moveSidebar(_ category: SyncaMessageCategory, by offset: Int) {
        let custom = syncManager.categories.filter { !$0.isDefault }
        guard !category.isDefault, let index = custom.firstIndex(where: { $0.id == category.id }), custom.indices.contains(index + offset) else { return }
        _ = reorderSidebar(category.id, to: custom[index + offset].id)
    }

    private func reorderSidebar(_ id: String, to target: String) -> Bool {
        guard !sidebarReordering else { return false }
        var ids = syncManager.categories.filter { !$0.isDefault }.map(\.id)
        guard let source = ids.firstIndex(of: id), let destination = ids.firstIndex(of: target), source != destination else { return false }
        ids.remove(at: source); ids.insert(id, at: destination)
        let orderedIDs = ids
        sidebarReordering = true
        Task { @MainActor in
            _ = await syncManager.reorderCategories(ids: orderedIDs)
            sidebarReordering = false
        }
        return true
    }

    private var accountAccessibilityValue: String {
        var parts = [api.currentUserEmail ?? ""]
        if let status = accessManager.status {
            parts.append(planName(status))
            if !status.isUnlimited, let limit = status.todayLimit, limit > 0 {
                parts.append("\(String(syncaLocalized: "account.today_records")) \(status.todayUsed) / \(limit)")
            }
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
    #endif

    private func planName(_ status: AccessStatus) -> String {
        String(syncaLocalized: status.isUnlimited ? "access.pro_name" : "access.free_title")
    }

    #if os(iOS)
    @ToolbarContentBuilder
    private var actionToolbarItems: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) { searchButton }
        ToolbarItem(placement: .topBarTrailing) {
            refreshButton.accessibilityLabel(Text("message_list.sync")).accessibilityIdentifier("phone-sync")
        }
        ToolbarItem(placement: .topBarTrailing) {
            clearAllButton.accessibilityIdentifier("phone-clear")
        }
        if !phoneLayout { ToolbarItem(placement: .topBarTrailing) {
            Button { showIOSSettings = true } label: { Image(systemName: "person.crop.circle") }
                .accessibilityLabel(Text("settings.title"))
                .keyboardShortcut(",", modifiers: .command)
        } }
    }

    @ToolbarContentBuilder
    private var titleToolbarItem: some ToolbarContent {
        if phoneLayout {
            ToolbarItem(placement: .topBarLeading) {
                Button { toggleDrawer(true) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 18, weight: .regular)).foregroundStyle(.secondary)
                        Text(selectedCategoryTitle)
                            .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            .lineLimit(1).truncationMode(.tail)
                        Text("\(todoCount(for: selectedFilterCategoryId))")
                            .font(.caption.weight(.semibold)).monospacedDigit()
                            .foregroundStyle(Color.primary.opacity(0.85))
                            .padding(.horizontal, 6)
                            .frame(minWidth: categoryBadgeDiameter, minHeight: categoryBadgeDiameter)
                            .background(categoryBadgeColor.opacity(colorScheme == .dark ? 0.24 : 0.14), in: Capsule())
                            .fixedSize().accessibilityHidden(true)
                    }
                    .frame(maxWidth: 154, minHeight: 44, alignment: .leading)

                }
                .accessibilityIdentifier("phone-categories")
                .accessibilityLabel(Text(selectedCategoryTitle) + Text("、") + Text(String(format: String(syncaLocalized: "message_list.pending_count"), todoCount(for: selectedFilterCategoryId))))
                .accessibilityHint(Text("message_category.section_title"))
            }
        } else {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 8) {
                Text("Synca")
                    .font(.system(size: 17, weight: .semibold))


            }
        }
        }
    }

    private var categoryBadgeColor: Color {
        guard let category = syncManager.categories.first(where: { $0.id == selectedFilterCategoryId }) else {
            return .secondary
        }
        return categoryDisplayColor(category.color, hex: category.colorHex)
    }

    /// UIKit arbitrates this edge drag before the feed's vertical pan can begin.
    private func handleDrawerEdgePan(_ state: UIGestureRecognizer.State, _ translation: CGFloat, _ velocity: CGFloat) {
        switch state {
        case .began, .changed:
            drawerTranslation = min(drawerWidth, max(0, translation))
        case .ended:
            let projectedTranslation = translation + velocity * DrawerEdgePan.projectionDuration
            toggleDrawer(projectedTranslation > drawerWidth * 0.4)
        case .cancelled, .failed:
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { drawerTranslation = 0 }
        default:
            break
        }
    }

    private func toggleDrawer(_ open: Bool) {
        if open { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.92)) {
            drawerOpen = open
            drawerTranslation = 0
        }
    }

    private func drawerRow(id: String, title: String, color: Color?, count: Int) -> some View {
        let selected = (syncManager.selectedCategoryId ?? syncManager.allCategoryPseudoId) == id
        return Button {
            syncManager.selectCategory(id)
            toggleDrawer(false)
        } label: {
            HStack(spacing: 10) {
                if let color { Circle().fill(color).frame(width: 9, height: 9) }
                else { Image(systemName: "square.grid.2x2") }
                Text(title).lineLimit(2)
                Spacer()
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24, alignment: .trailing)

            }.padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
             .background((color ?? Color.primary).opacity(selected ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 10))
             .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier("drawer-category-" + id)
         .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var phoneDrawer: some View {
        GeometryReader { proxy in
            let width = min(324, proxy.size.width * 0.82)
            let offset = min(0, max(-width, (drawerOpen ? 0 : -width) + drawerTranslation))
            let progress = 1 + offset / width
            ZStack(alignment: .leading) {
                Color.black.opacity(0.30 * progress).ignoresSafeArea()
                    .onTapGesture { toggleDrawer(false) }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image("LoginLogo").resizable().scaledToFit()
                            .frame(width: 32, height: 32).accessibilityHidden(true)
                        Text("Synca").font(.title2.bold())
                        Spacer()
                        Button { toggleDrawer(false) } label: { Image(systemName: "xmark").frame(width: 44,height: 44) }
                            .accessibilityLabel(Text("common.cancel"))
                    }
                    ScrollView {
                        VStack(spacing: 4) {
                            drawerRow(id: syncManager.allCategoryPseudoId, title: String(syncaLocalized: "common.all"), color: nil, count: allTodoCount)
                            HStack {
                                Text("message_category.section_title").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { toggleDrawer(false); showCategoryManager = true } label: { Image(systemName: "tag").font(.system(size: 18, weight: .regular)).foregroundStyle(.secondary).frame(width: 44, height: 44) }
                                    .accessibilityLabel(Text("message_list.manage_categories"))
                            }.padding(.leading,12)
                            ForEach(syncManager.categories) { category in
                                drawerRow(id: category.id, title: category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name, color: categoryDisplayColor(category.color, hex: category.colorHex), count: todoCount(for: category.id))
                            }
                            Button {
                                toggleDrawer(false); categoryToEdit = nil; showCreateCategory = true
                            } label: {
                                Image(systemName: "plus").foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 44)
                                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.secondary.opacity(0.22)))
                                    .contentShape(Rectangle())
                            }.accessibilityLabel(Text("message_category.add_action")).accessibilityIdentifier("drawer-add")
                        }
                    }
                    Divider()
                    Button { toggleDrawer(false); showIOSSettings = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "person.crop.circle.fill").font(.title2).foregroundStyle(.secondary)
                            Text(api.currentUserEmail ?? String(syncaLocalized: "account.and_plan"))
                                .font(.subheadline.weight(.medium)).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 8)
                            Image(systemName: "gearshape").font(.system(size: 19)).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("drawer-settings").keyboardShortcut(",", modifiers:.command)
                     .accessibilityLabel(Text("settings.title") + Text("、" + (api.currentUserEmail ?? String(syncaLocalized: "account.and_plan"))))
                    if let status = accessManager.status {
                        DailyQuotaView(status: status).padding(.horizontal, 12)
                            .accessibilityIdentifier("drawer-daily-quota")
                    }
                }
                .buttonStyle(.plain).padding(.horizontal,16).padding(.vertical,8)
                .frame(width: width)
                .frame(maxHeight:.infinity)
                .background(Color(uiColor:.secondarySystemBackground).ignoresSafeArea())
                .offset(x: offset)
                .simultaneousGesture(DragGesture(minimumDistance: 12)
                    .updating($drawerGestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        if categorySwipeIsHorizontal == nil {
                            categorySwipeIsHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                        }
                        guard categorySwipeIsHorizontal == true else { return }
                        drawerTranslation = min(0, max(-width, value.translation.width))
                    }
                    .onEnded { value in
                        defer { categorySwipeIsHorizontal = nil }
                        guard categorySwipeIsHorizontal == true else { return }
                        toggleDrawer(value.predictedEndTranslation.width > -width * 0.4)
                    })
                .accessibilityAction(.escape) { toggleDrawer(false) }
                .accessibilityElement(children: .contain)
            }
            .allowsHitTesting(drawerOpen)
            .accessibilityHidden(!drawerOpen)
            .onAppear { drawerWidth = width }
            .onChange(of: width) { drawerWidth = $0 }
        }
    }
    #endif

    // MARK: - Subviews

    private var isTiledLayout: Bool { false }

    private var selectedFilterCategoryId: String? {
        let selected = syncManager.selectedCategoryId
        if selected == syncManager.allCategoryPseudoId {
            return nil
        }
        return selected
    }

    private var activeSendCategoryId: String? {
        if syncManager.selectedCategoryId == syncManager.allCategoryPseudoId {
            return syncManager.categories.first(where: { $0.isDefault })?.id
        }
        return syncManager.selectedCategoryId
    }

    private var filteredMessages: [SyncaMessage] {
        syncManager.messages(for: selectedFilterCategoryId)
    }

    private var allTodoCount: Int {
        syncManager.todoCount()
    }

    private func todoCount(for categoryId: String?) -> Int {
        syncManager.todoCount(for: categoryId)
    }

    private var clearActionMessage: String {
        if isTiledLayout {
            return String(syncaLocalized: "message_list.clear_completed_all_categories", bundle: .main)
        }
        if let category = syncManager.categories.first(where: { $0.id == selectedFilterCategoryId }) {
            return String(
                format: String(syncaLocalized: "message_list.clear_completed_category_format", bundle: .main),
                category.name
            )
        }
        return String(syncaLocalized: "message_list.clear_completed_all_messages", bundle: .main)
    }

    private func switchCategory(horizontal: Double, vertical: Double) {
        let order = [syncManager.allCategoryPseudoId] + syncManager.categories.map(\.id)
        guard let target = CategorySwipeNavigation.target(order: order,
            selected: syncManager.selectedCategoryId ?? syncManager.allCategoryPseudoId,
            horizontal: horizontal, vertical: vertical) else { return }
        syncManager.selectCategory(target)
        #if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
        let title = syncManager.categories.first(where: { $0.id == target })?.name ?? String(syncaLocalized: "common.all")
        UIAccessibility.post(notification: .announcement, argument: title)
        #endif
    }

    @ViewBuilder
    private var categoryToolbar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(
                        title: String(syncaLocalized: "common.all", bundle: .main),
                        color: .primary,
                        neutral: true,
                        isSelected: syncManager.selectedCategoryId == syncManager.allCategoryPseudoId,
                        badgeCount: allTodoCount
                    ) {
                        syncManager.selectCategory(syncManager.allCategoryPseudoId)
                    }
                    .id(syncManager.allCategoryPseudoId)
                    Divider().frame(height: 20).padding(.horizontal, 4).accessibilityHidden(true)

                    ForEach(syncManager.categories) { category in
                        categoryChip(
                            title: category.isDefault ? String(syncaLocalized: "message_category.default_badge", bundle: .main) : category.name,
                            color: categoryDisplayColor(category.color, hex: category.colorHex),
                            isSelected: syncManager.selectedCategoryId == category.id,
                            badgeCount: todoCount(for: category.id)
                        ) {
                            syncManager.selectCategory(category.id)
                        }
                        .id(category.id)
                    }

                    Button {
                        categoryToEdit = nil
                        showCreateCategory = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.12), in: Circle())
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("message_category.add_action"))
                }
                .padding(.horizontal, 16)
                .padding(.top, 7)
            }
            .padding(.vertical, 10)
            .onChange(of: syncManager.selectedCategoryId) { selected in
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    proxy.scrollTo(selected ?? syncManager.allCategoryPseudoId, anchor: .center)
                }
            }
        }
    }

    private func categoryChip(title: String, color: Color, neutral: Bool = false, isSelected: Bool, badgeCount: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(isSelected ? .semibold : .regular))
                if badgeCount > 0 { Text(badgeCount, format: .number).font(.caption2.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background((neutral && isSelected ? Color.syncaPageBackground : color).opacity(isSelected ? 0.25 : 0.14), in: Capsule()) }
            }
            .foregroundStyle(neutral && isSelected ? Color.syncaPageBackground : Color.primary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(neutral ? Color.primary.opacity(isSelected ? 1 : 0.06) : color.opacity(isSelected ? 0.24 : 0.10), in: Capsule())
            .overlay { if neutral && !isSelected { Capsule().strokeBorder(Color.primary.opacity(0.10), lineWidth: 1) } }
            .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .accessibilityLabel(Text(String(format: String(syncaLocalized: "message_list.pending_count"), count)))
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
        categoryDisplayColor(color, hex: nil)
    }

    private func backgroundColor(for color: MessageCategoryColor) -> Color {
        categoryDisplayColor(color, hex: nil)
            .opacity([.amber, .violet, .ocean].contains(color) ? 0.18 : 0.16)
    }

    @ViewBuilder
    private var messageList: some View {
        let completed = filteredMessages.filter { $0.isCleared }
        let uncompleted = filteredMessages.filter { !$0.isCleared }

        if !syncManager.hasCompletedInitialLoad {
            ProgressView("message_list.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if completed.isEmpty && uncompleted.isEmpty {
            emptyStateView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        // One identity domain keeps image/text state while completion moves a row.
                        ForEach(completed + uncompleted, id: \.listRowID) { message in
                            if message.id == uncompleted.first?.id {
                                HStack {
                                    Text("message_list.todo_section", bundle: .main)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 8).padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.1)).cornerRadius(4)
                                    Spacer()
                                }.padding(.top, 8).id("uncompleted_header")
                            }
                            messageView(for: message, showsSeparator: message.id != (uncompleted.last?.id ?? completed.last?.id),
                                        onTextCollapse: { restoreCollapsedMessage(message, proxy: proxy) },
                                        onCompletion: { completePreservingViewport(message, proxy: proxy) })
                        }

                        Color.clear
                            .frame(height: 1 + completionBottomSpace)
                            .id("bottom")
                    }
                    #if os(iOS)
                    .background(FeedViewportReader(reference: feedViewport,
                        edgePanEnabled: phoneLayout && !drawerOpen,
                        onEdgePan: handleDrawerEdgePan))
                    #endif
                    .frame(maxWidth: streamMaximumWidth)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                #if os(iOS)
                                hideKeyboard()
                                #endif
                            }
                    )
                }
                .coordinateSpace(name: "search-feed")
                .accessibilityIdentifier("record-feed")
                .onPreferenceChange(SearchAnchorPosition.self) { searchAnchorY = $0 }
                .onPreferenceChange(SearchRowHeight.self) { searchRowHeight = $0 }
                #if os(iOS)
                .onPreferenceChange(SearchRowFrame.self) { searchRowFrame = $0 }
                .onPreferenceChange(RecordViewportFrames.self) { frames in
                    visibleRecordFrames = frames
                    if completionBottomSpace > 0, let scroll = feedViewport.scrollView,
                       scroll.isDragging || scroll.isDecelerating {
                        let naturalMaximum = max(-scroll.adjustedContentInset.top,
                            scroll.contentSize.height - completionBottomSpace - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        if scroll.contentOffset.y <= naturalMaximum { completionBottomSpace = 0 }
                    }
                }
                #endif
                .background(GeometryReader { geometry in
                    Color.clear.onAppear { searchViewportHeight = geometry.size.height }
                        .onChange(of: geometry.size.height) { searchViewportHeight = $0 }
                })
                .simultaneousGesture(DragGesture(minimumDistance: 4).onChanged { _ in
                    viewportInteractionRevision += 1
                    completionScrollTask?.cancel()
                    interruptSearchPositioning()
                })
                #if os(macOS)
                .background(SearchScrollInterruption(onScroll: interruptSearchPositioning))
                #endif
                .task(id: searchPositionRevision) {
                    guard let id = searchTarget else { return }
                    // Re-anchor as lazy rows resolve their heights; user input cancels immediately.
                    for delay in [80, 120, 200, 300, 400] {
                        try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                        guard !Task.isCancelled, searchTarget == id,
                              searchTargetCategory == syncManager.selectedCategoryId,
                              let message = filteredMessages.first(where: { $0.id == id }) else { return }
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        #if os(iOS)
                        positionSearchResult(message, proxy: proxy, transaction: transaction)
                        #else
                        let fits = searchRowHeight > 0 && searchRowHeight <= searchViewportHeight - 24
                        if fits || delay == 80 || searchAnchorY.map({ abs($0) > 2 }) != false {
                            withTransaction(transaction) {
                                proxy.scrollTo(fits || delay == 80 || searchMatchedText == nil ? message.listRowID : "search-hit-\(id)", anchor: fits ? .center : .top)
                            }
                        }
                        #endif
                        // Start feedback with the first positioning pass, not after
                        // all lazy-layout corrections (previously over a second).
                        if delay == 80 {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { searchHighlight = id }
                        }
                    }
                    guard searchTarget == id else { return }
                    #if os(iOS)
                    UIAccessibility.post(notification: .announcement, argument: String(syncaLocalized: "search.located"))
                    #else
                    NSAccessibility.post(element: NSApp.keyWindow as Any? ?? NSApp as Any,
                        notification: .announcementRequested,
                        userInfo: [.announcement: String(syncaLocalized: "search.located"), .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                    #endif
                    // Keep the target for genuinely late image sizing. Its independent
                    // highlight fades; any user navigation/scroll/edit cancels anchoring.
                }
                .onChange(of: searchImageRevision) { _ in
                    guard let id = searchTarget else { return }
                    scrollTask?.cancel()
                    scrollTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: Timing.scrollCoalescingNanoseconds)
                        guard !Task.isCancelled, searchTarget == id,
                              searchTargetCategory == syncManager.selectedCategoryId,
                              let message = filteredMessages.first(where: { $0.id == id }) else { return }
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        #if os(iOS)
                        positionSearchResult(message, proxy: proxy, transaction: transaction)
                        #else
                        let fits = searchRowHeight > 0 && searchRowHeight <= searchViewportHeight - 24
                        guard fits || searchAnchorY.map({ abs($0) > 2 }) != false else { return }
                        withTransaction(transaction) {
                            proxy.scrollTo(fits || searchMatchedText == nil ? message.listRowID : "search-hit-\(id)", anchor: fits ? .center : .top)
                        }
                        #endif
                    }
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
                    completionBottomSpace = 0
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
                    completionBottomSpace = 0
                    guard syncManager.hasCompletedInitialLoad else { return }
                    scrollToBottomAfterLayoutSettles(proxy: proxy)
                }
                .onAppear {
                    #if os(iOS)
                    if let target = collapsedRowTarget, target.category == syncManager.selectedCategoryId { return }
                    #endif
                    if syncManager.hasCompletedInitialLoad && !filteredMessages.isEmpty {
                        beginInitialLoadScrollWindow()
                        scrollToBottomAfterLayoutSettles(proxy: proxy)
                    }
                }
                #if os(iOS)
                .task(id: textLayoutRevision) {
                    guard let target = collapsedRowTarget,
                          target.category == syncManager.selectedCategoryId else { return }
                    // The replacement reader owns this task, so disappearance of
                    // the old reader cannot cancel restoration of the new layout.
                    try? await Task.sleep(nanoseconds: Timing.scrollCoalescingNanoseconds)
                    guard !Task.isCancelled else { return }
                    proxy.scrollTo(target.row, anchor: .top)
                    collapsedRowTarget = nil
                }
                #endif
                .onDisappear {
                    completionBottomSpace = 0
                    viewportInteractionRevision += 1
                    completionScrollTask?.cancel()
                    scrollTask?.cancel()
                    initialLoadScrollWindowID = UUID()
                    shouldScrollToBottomAfterInitialLoad = false
                }
            }
            // A filtered list must not inherit the previous category's lazy-row
            // estimates or scroll offset. Decoded thumbnails remain shared in
            // ImageCacheManager; only the feed's layout lifetime changes.
            .id("\(syncManager.selectedCategoryId ?? syncManager.allCategoryPseudoId)-\(textLayoutRevision)")
        }
    }

    @ViewBuilder
    private var syncStatusOverlay: some View {
        SyncStatusToastView(status: syncManager.syncStatus)
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
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            } icon: {
                Image(systemName: "xmark.circle.fill")
            }
            .font(.callout.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
            .frame(maxWidth: 480)
            .padding(.horizontal, 16)
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
                #if os(macOS)
                .frame(width: 44, height: 44).contentShape(Rectangle())
                #endif
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .keyboardShortcut("r", modifiers: .command)
        #endif
        .disabled(self.syncManager.isRefreshing)
    }

    private var clearAllButton: some View {
        Button {
            self.showClearAllConfirm = true
        } label: {
            Image("BroomOutline").resizable().scaledToFit()
                #if os(macOS)
                .frame(width: 18, height: 18)
                #else
                .frame(width: 26, height: 26)
                #endif
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("message_list.clear_completed"))
        .disabled((isTiledLayout ? syncManager.messages : filteredMessages).allSatisfy { !$0.isCleared })
    }

    @ViewBuilder
    private var managementMenuItems: some View {
        Button { showManagementMenu = false; showAccountInfo = true } label: { Label("account.and_plan", systemImage: "person.crop.circle") }
            #if os(macOS)
            .focused($managementMenuFocused)
            #endif
        Divider()
        Button { showManagementMenu = false; showAppSettings = true } label: { Label("settings.title", systemImage: "gearshape") }
            .keyboardShortcut(",", modifiers: .command)
        Button { showManagementMenu = false; showCategoryManager = true } label: { Label("message_list.manage_categories", systemImage: "tag") }
        Button { showManagementMenu = false; showAIConnection = true } label: { Label("message_list.connect_ai", systemImage: "sparkles") }
        Divider()
        Button { showManagementMenu = false; showFeedbackComposer = true } label: {
            #if os(macOS)
            Label { Text("message_list.feedback") } icon: {
                MacFeedbackIcon().stroke(style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)).frame(width: 18, height: 18)
            }
            #else
            Label("message_list.feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            #endif
        }
        Button { showManagementMenu = false; showAboutInfo = true } label: { Label("message_list.about", systemImage: "info.circle") }
        Button { showManagementMenu = false; showLogoutConfirm = true } label: { Label("message_list.sign_out", systemImage: "rectangle.portrait.and.arrow.right") }
    }

    private var settingsMenu: some View {
        Menu { managementMenuItems } label: { Image(systemName: "ellipsis.circle") }
            .buttonStyle(.plain).menuIndicator(.hidden)
            .accessibilityLabel(Text("account.menu"))
    }

    // MARK: - Input Bar

    private var composerControlSize: CGFloat {
        #if os(iOS)
        44
        #else
        30
        #endif
    }
    private var composerControlSpacing: CGFloat {
        #if os(iOS)
        0
        #else
        12
        #endif
    }
    private var composerHorizontalPadding: CGFloat {
        #if os(iOS)
        4
        #else
        16
        #endif
    }

    private var streamMaximumWidth: CGFloat {
        #if os(macOS)
        880
        #else
        760
        #endif
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: composerControlSpacing) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 9, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 20))
                    .frame(width: composerControlSize, height: composerControlSize).contentShape(Rectangle())
                    .accessibilityLabel(Text("message_list.add_photos"))
            }
            .buttonStyle(.plain)
            .disabled(syncManager.isSending)
            .opacity(syncManager.isSending ? 0.5 : 1.0)
            .onChange(of: self.selectedPhotoItems) { items in
                guard !items.isEmpty else { return }
                Task {
                    // Preserve the existing selected order, loading one original at a time.
                    let reversedItems = Array(items.reversed())
                    let targetCategoryId = activeSendCategoryId
                    self.selectedPhotoItems = []
                    shouldScrollToBottomAfterSend = true
                    await self.syncManager.sendImages(count: reversedItems.count, categoryId: targetCategoryId) { index in
                        try? await reversedItems[index].loadTransferable(type: Data.self)
                    }
                }
            }

            Button {
                showFileImporter = true
            } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: 20, weight: .medium))
                    .frame(width: composerControlSize, height: composerControlSize).contentShape(Rectangle())
                    .accessibilityLabel(Text("message_list.add_file"))
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
                    .frame(width: composerControlSize, height: composerControlSize).contentShape(Rectangle())
                    .accessibilityLabel(Text("message_list.send"))
                    .foregroundStyle(self.canSend ? Color.accentColor : Color.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
        }
        .padding(.horizontal, composerHorizontalPadding)
        #if os(macOS)
        .padding(.vertical, 8)
        #else
        .padding(.vertical, 4)
        #endif
        #if os(iOS)
        .background(Color.syncaInputFieldBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.syncaCardBorder, lineWidth: 1).allowsHitTesting(false))
        .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        .padding(.horizontal, 12).padding(.vertical, 8)
        #else
        .background(Color.syncaInputFieldBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.syncaCardBorder, lineWidth: 1))
        .padding(.horizontal, 20).padding(.vertical, 12)
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
            .frame(height: max(PasteAwareTextView.minimumHeight, min(inputHeight, PasteAwareTextView.maximumHeight)))
            .clipped()
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

        #else
        ZStack(alignment: .leading) {
            MacInputTextView(text: $inputText, height: $inputHeight, isSending: syncManager.isSending, placeholder: AppLocalization.string(syncManager.isSending ? "message_list.sending_placeholder" : "message_list.input_placeholder"), focusRequest: composerFocusRequest, onPasteImage: { imageData in
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


        }

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

    private var supportedAttachmentTypes: [UTType] { [.data] }

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
        await syncManager.sendFile(file: pendingFile, categoryId: categoryId)
    }

    private func completePreservingViewport(_ message: SyncaMessage, proxy: ScrollViewProxy) {
        #if os(iOS)
        let category = syncManager.selectedCategoryId
        viewportInteractionRevision += 1
        let revision = viewportInteractionRevision
        let candidates = visibleRecordFrames.filter { $0.key != message.id }
        let visible = candidates.filter { $0.value.maxY > 0 && $0.value.minY < searchViewportHeight }
        let neighbor = (visible.isEmpty ? candidates : visible).min { abs($0.value.minY) < abs($1.value.minY) }
        let originalOffset = feedViewport.scrollView?.contentOffset
        var extraBottomSpace: CGFloat = 0
        if !message.isCleared, let neighbor, let movingFrame = visibleRecordFrames[message.id],
           neighbor.value.minY < movingFrame.minY, let scroll = feedViewport.scrollView {
            // At the bottom, preserving a neighbor is impossible without the space of
            // the removed row: UIKit otherwise clamps the viewport down a whole image.
            // Release that temporary space once the reader scrolls back into real content.
            let availableBelow = max(0, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom - scroll.contentOffset.y)
            extraBottomSpace = max(0, movingFrame.height + 12 - availableBelow)
        }
        completionScrollTask?.cancel()
        Task { @MainActor in
            // Reading/navigation may cancel positioning, never the user's server mutation.
            await syncManager.clearMessage(message.id)
            guard revision == viewportInteractionRevision, category == syncManager.selectedCategoryId else { return }
            guard let updated = syncManager.messages.first(where: { $0.id == message.id }),
                  updated.isCleared != message.isCleared else { return }
            // Failed or superseded requests must never leave artificial content space.
            completionBottomSpace += extraBottomSpace
            completionScrollTask = Task { @MainActor in
                // Use the actual surviving row delta, not estimated lazy-stack height.
                // Viewport gestures invalidate this task, but never cancel the write.
                for delay in [30, 70, 150] {
                    try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000)
                    guard !Task.isCancelled, category == syncManager.selectedCategoryId,
                          revision == viewportInteractionRevision,
                          let scrollView = feedViewport.scrollView else { return }
                    let targetY: CGFloat
                    if let neighbor {
                        guard let currentFrame = visibleRecordFrames[neighbor.key] else {
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { proxy.scrollTo(neighbor.key, anchor: .top) }
                            continue
                        }
                        targetY = scrollView.contentOffset.y + currentFrame.minY - neighbor.value.minY
                    } else if let originalOffset {
                        targetY = originalOffset.y
                    } else { return }
                    let minimum = -scrollView.adjustedContentInset.top
                    let maximum = max(minimum, scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom)
                    scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: min(maximum, max(minimum, targetY))), animated: false)
                }
            }
        }
        #else
        Task { await syncManager.clearMessage(message.id) }
        #endif
    }

    private func restoreCollapsedMessage(_ message: SyncaMessage, proxy: ScrollViewProxy) {
        interruptSearchPositioning()
        scrollTask?.cancel()
        shouldScrollToBottomAfterInitialLoad = false
        shouldScrollToBottomAfterSend = false
        #if os(iOS)
        // LazyVStack can retain the expanded row's estimated height after a large
        // shrink. Rebuild its geometry; expanded states live above this identity.
        collapsedRowTarget = (syncManager.selectedCategoryId, message.listRowID)
        textLayoutRevision += 1
        #else
        let categoryID = syncManager.selectedCategoryId
        let rowID = message.listRowID
        scrollTask = Task { @MainActor in
            // A huge lazy row can shrink above the current viewport. Re-anchor after
            // SwiftUI commits the new height, rather than retaining the old offset.
            await Task.yield()
            guard !Task.isCancelled, categoryID == syncManager.selectedCategoryId else { return }
            proxy.scrollTo(rowID, anchor: .top)
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, categoryID == syncManager.selectedCategoryId else { return }
            proxy.scrollTo(rowID, anchor: .top)
        }
        #endif
    }

    private func scrollToBottomAfterLayoutSettles(proxy: ScrollViewProxy) {
        guard !searchScrollSuppressed, !searchPresentationSuppressesScroll, !showSearch else { return }
        scrollTask?.cancel()
        let categoryId = syncManager.selectedCategoryId
        scrollTask = Task { @MainActor in
            // Coalesce image-load notifications into a single pending scroll.
            try? await Task.sleep(nanoseconds: Timing.scrollCoalescingNanoseconds)
            guard !Task.isCancelled, categoryId == syncManager.selectedCategoryId else { return }
            #if os(macOS)
            proxy.scrollTo("bottom", anchor: .bottom)
            #else
            // scrollTo(bottom) can pull a short feed below its natural top while
            // the navigation bar establishes its initial adjusted inset. A feed
            // that already fits has nothing to reveal at the bottom.
            if let scrollView = feedViewport.scrollView,
               scrollView.contentSize.height <= scrollView.bounds.height
                    - scrollView.adjustedContentInset.top - scrollView.adjustedContentInset.bottom {
                scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: false)
                return
            }
            if shouldScrollToBottomAfterInitialLoad || reduceMotion {
                // Initial layout can change as lazy rows and attachments resolve their height.
                // Establish the final scroll geometry without animating intermediate offsets.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            } else {
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            #endif
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
        guard !searchScrollSuppressed, !searchPresentationSuppressesScroll else { return }
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
    private func messageView(for message: SyncaMessage, showsSeparator: Bool, onTextCollapse: (() -> Void)? = nil, onCompletion: (() -> Void)? = nil) -> some View {
        MessageBubbleView(
            message: message,
            categories: syncManager.categories,
            showsSeparator: false,
            isUpdatingCompletion: syncManager.completionUpdates.contains(message.id),
            onEdit: { editingMessage = message },
            onTextCollapse: onTextCollapse,
            onClear: {
                // Completing a row is explicit navigation intent. Late image loads must
                // not revive startup/send/search scrolling after the record moves.
                searchTarget = nil
                searchHighlight = nil
                scrollTask?.cancel()
                shouldScrollToBottomAfterInitialLoad = false
                shouldScrollToBottomAfterSend = false
                initialLoadScrollWindowID = UUID()
                postSendScrollWindowID = UUID()
                if let onCompletion { onCompletion() }
                else { Task { await syncManager.clearMessage(message.id) } }
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
                if searchTarget != nil { searchImageRevision += 1 }
                guard shouldScrollToBottomAfterSend || shouldScrollToBottomAfterInitialLoad else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    NotificationCenter.default.post(name: .syncaScrollToBottomAfterImageLoad, object: nil)
                }
            },
            textExpansion: textExpansionBinding(for: message.id),
            revealSearchText: searchTarget == message.id,
            searchMatchedText: searchTarget == message.id ? searchMatchedText : nil
        )
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(colorScheme == .dark
                      ? Color(red: 35 / 255, green: 73 / 255, blue: 108 / 255)
                      : Color(red: 217 / 255, green: 235 / 255, blue: 1))
                .padding(.vertical, 6)
                .opacity(searchHighlight == message.id ? 1 : 0)
        }
        .overlay(alignment: .bottom) {
            if showsSeparator { Divider().opacity(0.6).offset(y: 6) }
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: SearchRowHeight.self,
                value: searchTarget == message.id ? geometry.size.height : 0)
                #if os(iOS)
                .preference(key: RecordViewportFrames.self, value: [message.id: geometry.frame(in: .named("search-feed"))])
                .preference(key: SearchRowFrame.self,
                    value: searchTarget == message.id ? geometry.frame(in: .named("search-feed")) : nil)
                #endif
        })
        .id(message.listRowID)
    }

    #if os(iOS)
    private func positionSearchResult(_ message: SyncaMessage, proxy: ScrollViewProxy, transaction: Transaction) {
        let viewportInset: CGFloat = 12
        if let frame = searchRowFrame,
           frame.minY >= 0, frame.maxY <= searchViewportHeight {
            // A visible result needs emphasis, not another scroll. In particular,
            // centering the last row repeatedly fights the scroll view's bottom clamp.
            return
        }
        let fits = searchRowHeight > 0 && searchRowHeight <= searchViewportHeight - 2 * viewportInset
        let lastMessage = filteredMessages.last(where: { !$0.isCleared }) ?? filteredMessages.last
        withTransaction(transaction) {
            if !searchPositionedTextAnchor && (searchRowHeight == 0 || fits) {
                // Use the same anchor before and after lazy measurement resolves.
                proxy.scrollTo(message.listRowID, anchor: message.id == lastMessage?.id ? .bottom : .center)
            } else if let anchor = searchAnchorY, abs(anchor) <= 2 {
                return
            } else {
                // Expansion/lazy layout may temporarily report the collapsed height
                // again. Once navigating deep text, never jump back to the row anchor.
                searchPositionedTextAnchor = true
                proxy.scrollTo(searchMatchedText == nil ? message.listRowID : "search-hit-\(message.id)", anchor: .top)
            }
        }
    }
    #endif

    private func textExpansionBinding(for id: String) -> Binding<Bool>? {
        return Binding(
            get: { expandedTextIDs.contains(id) },
            set: { if $0 { expandedTextIDs.insert(id) } else { expandedTextIDs.remove(id) } }
        )
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
                        TiledCategoryColumn(category: category, onEdit: { editingMessage = $0 })
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
        return String(syncaLocalized: "message_file.error_image_too_large", bundle: .main)
    }
    if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > PendingFileUpload.maxFileSize {
        return String(syncaLocalized: "message_file.error_too_large", bundle: .main)
    }
    return String(syncaLocalized: "message_file.error_unsupported", bundle: .main)
}

private struct TiledCategoryColumn: View {
    static let minWidth: CGFloat = 420

    @EnvironmentObject var syncManager: SyncManager
    let category: SyncaMessageCategory
    let onEdit: (SyncaMessage) -> Void

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
            .accessibilityLabel(Text(String(format: String(syncaLocalized: "message_list.pending_count"), count)))
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
                Text(category.isDefault ? String(syncaLocalized: "message_category.default_badge", bundle: .main) : category.name)
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
                    Task { await syncManager.refresh() }
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
                                showsSeparator: message.id != (pendingMessages.last?.id ?? completedMessages.last?.id),
                                isUpdatingCompletion: syncManager.completionUpdates.contains(message.id),
                                onEdit: { onEdit(message) },
                                onClear: { Task { await syncManager.clearMessage(message.id) } },
                                onDelete: {
                                    Task { await syncManager.deleteMessage(message.id) }
                                },
                                onCategoryChange: { categoryId in
                                    Task { await syncManager.updateMessageCategory(message.id, categoryId: categoryId) }
                                },
                                onImageTap: {},
                                onImageLoaded: {}
                            )
                            .id(message.listRowID)
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
                                showsSeparator: message.id != (pendingMessages.last?.id ?? completedMessages.last?.id),
                                isUpdatingCompletion: syncManager.completionUpdates.contains(message.id),
                                onEdit: { onEdit(message) },
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
                            .id(message.listRowID)
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
                            file: pendingFile,
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
                        let reversedItems = Array(items.reversed())
                        let targetCategoryId = category.id
                        selectedPhotoItems = []
                        await syncManager.sendImages(count: reversedItems.count, categoryId: targetCategoryId) { index in
                            try? await reversedItems[index].loadTransferable(type: Data.self)
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

                TextField(String(syncaLocalized: "message_list.input_placeholder", bundle: .main), text: $inputText, axis: .vertical)
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
        categoryDisplayColor(color, hex: category.colorHex)
            .opacity([.amber, .violet, .ocean].contains(color) ? 0.18 : 0.16)
    }

    private var supportedAttachmentTypes: [UTType] { [.data] }

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
                file: pendingFile,
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

        private static var supportedAttachmentTypes: [UTType] { [.data] }
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
    let placeholder = NSTextField(labelWithString: AppLocalization.string("message_list.input_placeholder"))

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

    let category: SyncaMessageCategory?
    let onManageCategories: () -> Void
    let showsManageCategories: Bool

    init(category: SyncaMessageCategory? = nil, showsManageCategories: Bool = true, onManageCategories: @escaping () -> Void) {
        self.category = category
        self.showsManageCategories = showsManageCategories
        self.onManageCategories = onManageCategories
        _name = State(initialValue: category?.name ?? "")
        _color = State(initialValue: category?.color ?? .sky)
        _colorHex = State(initialValue: category?.colorHex)
    }

    @State private var name = ""
    @State private var color: MessageCategoryColor = .sky
    @State private var colorHex: String?
    @State private var showPalette = false
    @State private var showDuplicateNameAlert = false
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var showDiscardConfirm = false
    @State private var pendingManage = false

    private var hasChanges: Bool {
        name != (category?.name ?? "") || color != (category?.color ?? .sky) || colorHex != category?.colorHex
    }

    private func requestClose(manage: Bool = false) {
        guard !isSaving else { return }
        pendingManage = manage
        if hasChanges { showDiscardConfirm = true } else { finishClose() }
    }

    private func finishClose() {
        if pendingManage { onManageCategories() } else { dismiss() }
    }

    #if os(iOS)
    @FocusState private var isNameFocused: Bool
    #endif

    private var paletteButton: some View {
        Button { showPalette = true } label: {
            HStack(spacing: 8) {
                Circle().fill(categoryDisplayColor(color, hex: colorHex)).frame(width: 22, height: 22)
                Text("message_category.color_label").foregroundStyle(.primary)
            }.frame(minHeight: 44)
        }.buttonStyle(.plain)
            .popover(isPresented: $showPalette) {
                CategoryPresetPicker(selectedHex: colorHex, legacy: color) { preset in
                    color = preset.legacy; colorHex = preset.hex; showPalette = false
                }.modifier(CompactCategoryPopover())
            }
    }

    private var canCreate: Bool {
        !isSaving && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isDuplicateCategoryName(_ name: String) -> Bool {
        syncManager.categories.contains { category in
            category.id != self.category?.id && category.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(name) == .orderedSame
        }
    }

    private func createCategory() {
        guard !isSaving else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard category?.isDefault == true || !isDuplicateCategoryName(trimmed) else {
            showDuplicateNameAlert = true
            return
        }

        isSaving = true
        Task {
            let saved: Bool
            if let category {
                if category.isDefault {
                    saved = await syncManager.updateCategory(id: category.id, color: color, colorHex: colorHex)
                }
                else {
                    let paletteChanged = color != category.color || colorHex != category.colorHex
                    saved = await syncManager.updateCategory(id: category.id, name: trimmed,
                        color: paletteChanged ? color : nil, colorHex: paletteChanged ? colorHex : nil)
                }
            } else {
                saved = await syncManager.createCategory(name: trimmed, color: color, colorHex: colorHex) != nil
            }
            isSaving = false
            if saved { dismiss() } else { showSaveError = true }
        }
    }

    var body: some View {
        Group {
        #if os(iOS)
        NavigationStack {
            Form {
                Section {
                    if category?.isDefault == true {
                        Text("message_category.default_badge").foregroundStyle(.secondary)
                    } else {
                    TextField(String(syncaLocalized: "message_category.name_placeholder", bundle: .main), text: $name)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit {
                            if canCreate {
                                createCategory()
                            }
                        }
                    }
                }

                Section {
                    CategoryPresetPicker(selectedHex: colorHex, legacy: color, expandsToFill: true) { preset in
                        color = preset.legacy
                        colorHex = preset.hex
                    }
                }

                if showsManageCategories {
                    Section {
                        Button {
                            requestClose(manage: true)
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
            }
            .scrollContentBackground(.hidden)
            .background(Color.syncaPageBackground)
            .navigationTitle(category == nil ? "message_category.new_section" : "message_category.edit_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { requestClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(category == nil ? "common.add" : "common.save") {
                        createCategory()
                    }
                    .disabled(!canCreate)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                isNameFocused = category?.isDefault != true
            }
        }
        .alert("message_category.duplicate_title", isPresented: $showDuplicateNameAlert) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("message_category.duplicate_message")
        }
        #else
        VStack(spacing: 0) {
            MacSheetHeader(title: category == nil ? "message_category.new_section" : "message_category.edit_title", onClose: { requestClose() })

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                Group {
                    if category?.isDefault == true {
                        Text("message_category.default_badge")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        TextField(String(syncaLocalized: "message_category.name_placeholder", bundle: .main), text: $name)
                            .textFieldStyle(.plain)
                    }
                }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(Color.syncaInputFieldBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.syncaInputFieldBorder, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 10) {
                    CategoryPresetPicker(selectedHex: colorHex, legacy: color, columnCount: 8) { preset in
                        color = preset.legacy
                        colorHex = preset.hex
                    }
                }
            }
            .padding(20)

            Divider()

            HStack(spacing: 12) {
                if showsManageCategories {
                    Button {
                        requestClose(manage: true)
                    } label: {
                        Text("message_list.manage_categories", bundle: .main)
                            .font(.callout.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                }

                Spacer()

                Button("common.cancel", role: .cancel) { requestClose() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.primary)
                    .keyboardShortcut(.cancelAction)

                Button(category == nil ? "message_category.add_action" : "common.save") {
                    createCategory()
                }
                .disabled(!canCreate)
                .buttonStyle(MacPrimaryActionButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
        .alert("message_category.duplicate_title", isPresented: $showDuplicateNameAlert) {
            Button("common.ok", role: .cancel) {}
        } message: {
            Text("message_category.duplicate_message")
        }
        .frame(width: min(420, (NSScreen.main?.visibleFrame.width ?? 520) - 80))
        #endif
        }
        .disabled(isSaving)
        .interactiveDismissDisabled(hasChanges || isSaving)
        .modifier(DiscardChangesConfirmation(isPresented: $showDiscardConfirm, onDiscard: { finishClose() }))
        .alert("message_category.save_failed_title", isPresented: $showSaveError) {
            Button("common.ok", role: .cancel) {}
        } message: { Text("message_category.save_failed_message") }
    }
}

struct MessageCategoryManagerSheet: View {
    var embedded = false
    #if os(iOS)
    @State private var editingCategory: SyncaMessageCategory?
    #endif
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: SyncaMessageCategory?
    @State private var busy = false
    @State private var failed = false
    @State private var adding = false
    @State private var draftNames: [String: String] = [:]

    private func finish() {
        guard !busy else { return }
        let pending = syncManager.categories.filter { !$0.isDefault }.compactMap { category -> (String, String)? in
            guard let draft = draftNames[category.id] else { return nil }
            let name = draft.trimmingCharacters(in: .whitespacesAndNewlines)
            return name == category.name ? nil : (category.id, name)
        }
        let names = syncManager.categories.map { (draftNames[$0.id] ?? $0.name).trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase }
        guard !names.contains(where: \.isEmpty), Set(names).count == names.count else { failed = true; return }
        busy = true
        Task { @MainActor in
            for (id, name) in pending {
                guard await syncManager.updateCategory(id: id, name: name) else { busy = false; failed = true; return }
            }
            busy = false
            dismiss()
        }
    }

    private func perform(_ operation: @escaping @MainActor () async -> Bool) {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            let succeeded = await operation()
            busy = false
            if !succeeded { failed = true }
        }
    }

    private func rename(_ category: SyncaMessageCategory, name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !category.isDefault, name != category.name else { return }
        guard !name.isEmpty, !syncManager.categories.contains(where: {
            $0.id != category.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }) else { failed = true; return }
        perform { await syncManager.updateCategory(id: category.id, name: name) }
    }

    private func move(_ id: String, to target: String) {
        var ids = syncManager.categories.filter { !$0.isDefault }.map(\.id)
        guard let source = ids.firstIndex(of: id), let destination = ids.firstIndex(of: target), source != destination else { return }
        ids.remove(at: source)
        ids.insert(id, at: destination)
        let orderedIDs = ids
        // Keep the authoritative order visible until the server accepts it; failure needs no rollback.
        perform { await syncManager.reorderCategories(ids: orderedIDs) }
    }

    private func move(_ category: SyncaMessageCategory, by offset: Int) {
        let custom = syncManager.categories.filter { !$0.isDefault }
        guard let index = custom.firstIndex(where: { $0.id == category.id }), custom.indices.contains(index + offset) else { return }
        move(category.id, to: custom[index + offset].id)
    }

    private func categoryRow(_ category: SyncaMessageCategory) -> some View {
        InlineCategoryRow(category: category, busy: busy, draftName: draftNames[category.id],
            onRename: { rename(category, name: $0) },
            onDraftName: { draftNames[category.id] = $0 },
            onColor: { preset in
                perform { await syncManager.updateCategory(id: category.id, color: preset.legacy, colorHex: preset.hex) }
            },
            onDelete: { pendingDelete = category },
            onMoveUp: { move(category, by: -1) }, onMoveDown: { move(category, by: 1) }, onExit: finish)
    }

    private var addButton: some View {
        Button { adding = true } label: {
            Label("message_category.add_action", systemImage: "plus")
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }.buttonStyle(.plain).disabled(busy)
    }

    #if os(iOS)
    private func nativeRow(_ category: SyncaMessageCategory) -> some View {
        HStack(spacing: 0) {
            Button { editingCategory = category } label: {
                HStack(spacing: 12) {
                    Circle().fill(categoryDisplayColor(category.color, hex: category.colorHex))
                        .frame(width: 10, height: 10).accessibilityHidden(true)
                    Text(category.isDefault ? AppLocalization.string("message_category.default_badge") : category.name)
                        .foregroundStyle(.primary).lineLimit(2)
                    Spacer(minLength: 8)
                }.frame(minHeight: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("category-edit-" + category.id)
             .accessibilityHint(Text("message_category.modify"))
            if !category.isDefault {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 16)).foregroundStyle(.tertiary)
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(Text("message_category.reorder") + Text(" " + category.name))
                    .accessibilityIdentifier("category-reorder-" + category.id)
                    .accessibilityAction(named: Text("message_category.move_up")) { move(category, by: -1) }
                    .accessibilityAction(named: Text("message_category.move_down")) { move(category, by: 1) }
                Button { pendingDelete = category } label: {
                    Image(systemName: "trash").font(.system(size: 16)).foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(Text("message_category.delete_action") + Text(" " + category.name))
                 .accessibilityIdentifier("category-delete-" + category.id)
            }
        }.padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 2).disabled(busy)
         .background(Color(uiColor: .secondarySystemGroupedBackground))
    }

    private var rows: some View {
        ScrollView {
            VStack(spacing: 0) {
                CategoryReorderStack(categories: syncManager.categories, spacing: 0, handleOnly: true,
                    handleTrailingInset: 52, handleWidth: 44, disabled: busy, onCommit: { ids in
                        busy = true
                        if !(await syncManager.reorderCategories(ids: ids)) { failed = true }
                        busy = false
                    }) { category in
                        nativeRow(category)
                            .overlay(alignment: .bottom) { Divider().padding(.leading, 38) }
                    }
                addButton.padding(.horizontal, 16).padding(.vertical, 4)
            }
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("message_list.manage_categories")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !embedded {
                ToolbarItem(placement: .cancellationAction) { Button("common.close") { dismiss() }.disabled(busy) }
            }
        }
        .tint(.primary)
        .sheet(item: $editingCategory) { category in
            NewMessageCategorySheet(category: category, showsManageCategories: false, onManageCategories: {})
                .syncaPreferences()
        }
    }
    #else
    private var rows: some View {
        VStack(spacing: 0) {
            CategoryReorderStack(categories: syncManager.categories, spacing: 0, handleOnly: true, disabled: busy, onCommit: { ids in
                busy = true
                if !(await syncManager.reorderCategories(ids: ids)) { failed = true }
                busy = false
            }, onExit: {
                guard !adding, pendingDelete == nil, !failed else { return }
                finish()
            }) { category in
                categoryRow(category)
            }
        }
        .background(Color.syncaCardBackground, in: RoundedRectangle(cornerRadius: 12))
        .padding(20)
    }
    #endif

    var body: some View {
        Group {
            #if os(iOS)
            if embedded { rows } else { NavigationStack { rows } }
            #else
            VStack(spacing: 0) {
                MacSheetHeader(title: "message_list.manage_categories", onClose: finish)
                Divider()
                ScrollView { rows }.frame(maxHeight: 540)
                Divider()
                HStack(spacing: 12) {
                    Button { adding = true } label: {
                        Label("message_category.add_action", systemImage: "plus")
                    }.buttonStyle(.plain).disabled(busy)
                    Spacer()
                    Button("common.done", action: finish)
                        .buttonStyle(MacPrimaryActionButtonStyle())
                        .keyboardShortcut(.defaultAction)
                        .disabled(busy)
                }.padding(20)
            }.frame(width: 480, height: min(620, CGFloat(syncManager.categories.count) * 64 + 180))
            #endif
        }
        .sheet(isPresented: $adding) {
            NewMessageCategorySheet(showsManageCategories: false, onManageCategories: { adding = false })
                .environmentObject(syncManager)
                .syncaPreferences()
                #if os(iOS)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                #endif
        }
        .interactiveDismissDisabled(busy)
        .alert("message_category.save_failed_title", isPresented: $failed) {
            Button("common.ok", role: .cancel) {}
        } message: { Text("message_category.save_failed_message") }
        .alert("message_category.delete_confirm_title", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button("common.cancel", role: .cancel) { pendingDelete = nil }
            Button("common.delete", role: .destructive) {
                if let category = pendingDelete { perform { await syncManager.deleteCategory(id: category.id) } }
                pendingDelete = nil
            }
        } message: { Text("message_category.delete_confirm_message") }
    }
}

private struct InlineCategoryRow: View {
    let category: SyncaMessageCategory
    let busy: Bool
    let draftName: String?
    let onRename: (String) -> Void
    let onDraftName: (String) -> Void
    let onColor: (CategoryColorPreset) -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    var onExit: (() -> Void)? = nil
    @State private var name = ""
    @State private var palettePresented = false
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 4) {
            Button { palettePresented = true } label: {
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(categoryDisplayColor(category.color, hex: category.colorHex))
                        .frame(width: 18, height: 18)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }.frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(Text("message_category.color_label"))
                .popover(isPresented: $palettePresented) {
                    CategoryPresetPicker(selectedHex: category.colorHex, legacy: category.color) { preset in
                        palettePresented = false; onColor(preset)
                    }.modifier(CompactCategoryPopover())
                }
                TextField("message_category.name_placeholder", text: category.isDefault ? .constant(String(syncaLocalized: "message_category.default_badge")) : $name)
                    .textFieldStyle(.plain).focused($editing)
                    #if os(iOS)
                    // Keep the input independent of List's persistent reorder mode.
                    .environment(\.editMode, .constant(.inactive))
                    #endif
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
                    .accessibilityLabel(Text("message_category.name_placeholder"))
                    #if os(iOS)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = true }
                    #endif
                    .disabled(category.isDefault)
                    #if os(macOS)
                    .onExitCommand { onExit?() }
                    #endif
                    .onSubmit { editing = false }
                    .onChange(of: name) { onDraftName($0) }
                    .onChange(of: editing) { focused in if !focused { onRename(name) } }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash").frame(width: 44, height: 44)
                }.buttonStyle(.plain).accessibilityLabel(Text("message_category.delete_action"))
                    .disabled(category.isDefault)
                    .opacity(category.isDefault ? 0.3 : 1)
                #if os(macOS)
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                    .frame(width: 28, height: 44).opacity(category.isDefault ? 0.3 : 1).accessibilityHidden(true)
                #else
                if category.isDefault {
                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                        .frame(width: 24, height: 44).opacity(0.3).accessibilityHidden(true)
                }
                #endif
        }
        .font(.body).padding(.horizontal, 8).padding(.vertical, 4)
        .disabled(busy)
        .onAppear { name = draftName ?? category.name }
        // A returned category confirms a successful rename. Busy ending alone does not:
        // keep the local draft on network failure so Done or submit can retry it.
        .onChange(of: category.name) { if !editing { name = $0 } }
        .accessibilityAction(named: Text("message_category.move_up")) { if !category.isDefault { onMoveUp() } }
        .accessibilityAction(named: Text("message_category.move_down")) { if !category.isDefault { onMoveDown() } }
    }
}

private struct CompactCategoryPopover: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        #if os(iOS)
        if #available(iOS 16.4, *) { content.presentationCompactAdaptation(.popover) }
        else { content.presentationDetents([.height(220)]) }
        #else
        content
        #endif
    }
}

private struct CategoryPresetPicker: View {
    let selectedHex: String?
    let legacy: MessageCategoryColor
    var columnCount: Int = 4
    var expandsToFill = false
    let onSelect: (CategoryColorPreset) -> Void
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(expandsToFill ? .flexible(minimum: 44) : .fixed(44), spacing: 0), count: columnCount), spacing: expandsToFill ? 8 : 0) {
            ForEach(CategoryColorPreset.all) { preset in
                let colorNameKey = "message_category.color.\(preset.name)"
                let selected = CategoryColorPreset.resolved(legacy: legacy, hex: selectedHex).hex == preset.hex
                Button { onSelect(preset) } label: {
                    Circle().fill(categoryDisplayColor(preset.legacy, hex: preset.hex))
                        .frame(width: 28, height: 28)
                        .overlay { if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).shadow(color: .black.opacity(0.6), radius: 1) } }
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: AppLocalization.string(colorNameKey)))
                    .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }.padding(10)
            .frame(width: expandsToFill ? nil : CGFloat(columnCount) * 44 + 20)
            .frame(maxWidth: expandsToFill ? .infinity : nil)
    }
}

/// Use the same explicit RGB value for legacy categories and palette selections.
func categoryDisplayColor(_ legacy: MessageCategoryColor, hex: String?) -> Color {
    let preset = CategoryColorPreset.resolved(legacy: legacy, hex: hex)
    guard let rgb = UInt32(preset.hex.dropFirst(), radix: 16) else { return .secondary }
    return Color(red: Double((rgb >> 16) & 255) / 255, green: Double((rgb >> 8) & 255) / 255, blue: Double(rgb & 255) / 255)
}

struct AboutSyncaSheet: View {
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var contentHeight: CGFloat = 360

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
            format: String(syncaLocalized: "message_list.about_version_format", bundle: .main),
            version,
            build
        )
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacSheetHeader(title: "message_list.about")
            Divider()
            sheetContent
        }
        .frame(width: min(420, (NSScreen.main?.visibleFrame.width ?? 520) - 80), height: min(contentHeight + 57, (NSScreen.main?.visibleFrame.height ?? 860) - 100))

        #else
        if embedded { sheetContent } else {
        NavigationStack {
            sheetContent
                .navigationTitle(Text("message_list.about"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { closeButton }
                }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight + 60), .large])
        }
        #endif
    }

    private var closeButton: some View {
        Button("common.close") { dismiss() }
            #if os(macOS)
            .buttonStyle(.bordered)
            .foregroundStyle(.primary)
            .keyboardShortcut(.cancelAction)
            #endif
    }

    private var linkMinimumHeight: CGFloat {
        #if os(iOS)
        44
        #else
        36
        #endif
    }

    private func aboutLink(_ title: LocalizedStringKey, destination: URL) -> some View {
        Link(destination: destination) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: linkMinimumHeight)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                    .allowsHitTesting(false))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private var sheetContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                HStack(spacing: 14) {
                    Image("LoginLogo").resizable().scaledToFit()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Synca").font(.title2.weight(.semibold))
                        Text(versionText).font(.subheadline).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity).padding(.top, 0)
                Text(String(syncaLocalized: "app.slogan", bundle: .main))
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                VStack(spacing: 12) {
                    DeveloperSocialLink(title: "developer_social.follow")
                    HStack(spacing: 12) {
                        aboutLink("access.privacy_policy_link_title", destination: AppLinks.privacyPolicyURL)
                        aboutLink("message_list.support", destination: AppLinks.supportURL)
                    }
                }.padding(.top, 28)

                #if os(macOS)
                Text(verbatim: "浙ICP备2026013056号-3A")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 12)
            .background(GeometryReader { proxy in
                Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
            })
        }
        .scrollIndicators(.hidden)
        .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
        .background(sheetBackgroundColor)
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
            .syncaPreferences()
        }
        #else
        self.sheet(item: item) { msg in
            let allImages = syncManager.imageMessages
            let initialIndex = allImages.firstIndex(where: { $0.id == msg.id }) ?? 0
            ImagePreviewView(messages: allImages, initialIndex: initialIndex) { deletedId in
                Task { await syncManager.deleteMessage(deletedId) }
            }
            .frame(minWidth: 800, minHeight: 600)
            .syncaPreferences()
        }
        #endif
    }
}

#if os(macOS)
private struct ManagementMenuLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon.frame(width: 18, height: 18)
            configuration.title
        }
    }
}
private struct ManagementMenuRowStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(ManagementMenuLabelStyle())
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(Color.primary.opacity(configuration.isPressed ? 0.14 : isHovered ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 8))
            .onHover { isHovered = $0 }
    }
}
#endif

/// iOS needs a navigation bar; the desktop owns its full-height split layout.
/// A desktop NavigationStack reserves a titlebar row even with an empty title.
private struct MessageListNavigationContainer<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if os(macOS)
        content()
            .ignoresSafeArea(.container, edges: .top)
            .toolbarBackground(.hidden, for: .windowToolbar)
        #else
        NavigationStack { content() }
        #endif
    }
}

/// Local pointer reordering: the row follows the pointer, siblings make room, and only the final order is saved.
/// No pasteboard drag session is created, so reordering never advertises a copy operation.
private struct CategoryRowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct CategoryReorderStack<Row: View>: View {
    let categories: [SyncaMessageCategory]
    let spacing: CGFloat
    let handleOnly: Bool
    var handleTrailingInset: CGFloat = 0
    var handleWidth: CGFloat = 36
    let disabled: Bool
    let onCommit: ([String]) async -> Void
    var onExit: (() -> Void)? = nil
    @ViewBuilder let row: (SyncaMessageCategory) -> Row
    @State private var coordinateID = UUID()
    @State private var frames: [String: CGRect] = [:]
    @State private var originalFrames: [String: CGRect] = [:]
    @State private var originalIDs: [String] = []
    @State private var previewIDs: [String] = []
    @State private var draggedID: String?
    @GestureState private var gestureInFlight = false
    @State private var gestureCancelled = false
    @State private var gestureGeneration = UUID()
    @State private var translation: CGFloat = 0
    @State private var saving = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    private var ordered: [SyncaMessageCategory] {
        guard !previewIDs.isEmpty else { return categories }
        let lookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return categories.filter(\.isDefault) + previewIDs.compactMap { lookup[$0] }
    }
    var body: some View {
        VStack(spacing: spacing) {
            ForEach(ordered) { category in
                row(category)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: CategoryRowFrames.self, value: [category.id: geometry.frame(in: .named(coordinateID))])
                    })
                    .overlay(alignment: .trailing) {
                        if handleOnly && !category.isDefault {
                            Color.clear.frame(width: handleWidth).contentShape(Rectangle()).gesture(drag(category))
                                .padding(.trailing, handleTrailingInset).accessibilityHidden(true)
                        }
                    }
                    .highPriorityGesture(handleOnly || category.isDefault ? nil : drag(category))
                    .offset(y: dragOffset(for: category.id))
                    .transaction { if draggedID == category.id { $0.animation = nil } }
                    .zIndex(draggedID == category.id ? 1 : 0)
                    .shadow(color: .black.opacity(draggedID == category.id ? 0.12 : 0), radius: 5, y: 2)
            }
        }
        .coordinateSpace(name: coordinateID)
        .onPreferenceChange(CategoryRowFrames.self) { frames = $0 }
        // Animate actual placement changes, not clearing the preview after a save.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: ordered.map(\.id))
        // Block duplicate interactions without dimming every category during the request.
        .allowsHitTesting(!saving)
        .onChange(of: gestureInFlight) { active in
            guard !active else { return }
            let generation = gestureGeneration
            // Let a successful onEnded capture/commit its order before cancellation cleanup.
            DispatchQueue.main.async {
                guard !gestureInFlight, !saving, generation == gestureGeneration else { return }
                gestureCancelled = false
                reset()
            }
        }
        #if os(macOS)
        .onExitCommand {
            guard !saving, !disabled else { return }
            if gestureInFlight || draggedID != nil {
                gestureCancelled = gestureInFlight
                reset()
            } else {
                onExit?()
            }
        }
        #endif
        .onDisappear { if !saving { reset() } }
        .onChange(of: categories.map(\.id)) { _ in if !saving { gestureCancelled = gestureInFlight; reset() } }
    }
    private func dragOffset(for id: String) -> CGFloat {
        guard draggedID == id, let original = originalFrames[id],
              let firstY = originalFrames.values.map(\.minY).min() else { return 0 }
        let currentY = ordered.prefix(while: { $0.id != id }).reduce(firstY) {
            $0 + (originalFrames[$1.id]?.height ?? 0) + spacing
        }
        return original.minY + translation - currentY
    }
    private func drag(_ category: SyncaMessageCategory) -> some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .named(coordinateID))
            .updating($gestureInFlight) { _, active, _ in active = true }
            .onChanged { value in
                guard !disabled, !saving, !gestureCancelled, !category.isDefault else { return }
                if draggedID == nil {
                    gestureGeneration = UUID()
                    draggedID = category.id
                    originalFrames = frames
                    originalIDs = categories.filter { !$0.isDefault }.map(\.id)
                    previewIDs = originalIDs
                }
                guard draggedID == category.id, let origin = originalFrames[category.id] else { return }
                translation = value.translation.height
                let center = origin.midY + translation
                guard let nearest = originalIDs.min(by: { abs((originalFrames[$0]?.midY ?? center) - center) < abs((originalFrames[$1]?.midY ?? center) - center) }),
                      let destination = originalIDs.firstIndex(of: nearest) else { return }
                var ids = originalIDs.filter { $0 != category.id }
                ids.insert(category.id, at: min(destination, ids.count))
                if previewIDs != ids { previewIDs = ids }
            }
            .onEnded { value in
                defer { gestureCancelled = false }
                guard !gestureCancelled, draggedID == category.id else { return }
                let bounds = originalFrames.values.reduce(CGRect.null) { $0.union($1) }.insetBy(dx: -24, dy: -24)
                guard bounds.contains(value.location) else { reset(); return }
                let ids = previewIDs
                draggedID = nil; translation = 0
                guard ids != originalIDs else { reset(); return }
                saving = true
                Task { @MainActor in
                    await onCommit(ids)
                    saving = false
                    reset()
                }
            }
    }
    private func reset() { draggedID = nil; translation = 0; previewIDs = []; originalIDs = []; originalFrames = [:] }
}

// LazyVStack must know offscreen scroll targets through ForEach identity, before
// messageView is materialized. Use the same identity for collapse and search.
private extension SyncaMessage {
    var listRowID: String { id }
}

/// Read-only geometry; emphasis never inserts padding or affects measurement.
struct SearchAnchorPosition: PreferenceKey {
    static var defaultValue: CGFloat? { nil }
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = next }
    }
}

/// The selected card's full bounds determine whether to reveal the whole card or a deep text hit.
private struct SearchRowHeight: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct SearchRowFrame: PreferenceKey {
    static var defaultValue: CGRect? { nil }
    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        if let next = nextValue() { value = next }
    }
}

private struct RecordViewportFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}

#if os(iOS)
@MainActor private final class FeedViewportReference {
    weak var scrollView: UIScrollView?
}
private enum DrawerEdgePan {
    static let activationWidth: CGFloat = 32
    static let horizontalBias: CGFloat = 1.5
    static let projectionDuration: CGFloat = 0.2
}

private struct FeedViewportReader: UIViewRepresentable {
    let reference: FeedViewportReference
    let edgePanEnabled: Bool
    let onEdgePan: (UIGestureRecognizer.State, CGFloat, CGFloat) -> Void

    func makeUIView(context: Context) -> Probe { Probe(reference: reference) }
    func updateUIView(_ uiView: Probe, context: Context) {
        uiView.onEdgePan = onEdgePan
        if uiView.edgePan.isEnabled != edgePanEnabled { uiView.edgePan.isEnabled = edgePanEnabled }
        uiView.resolve()
    }
    static func dismantleUIView(_ uiView: Probe, coordinator: ()) { uiView.detach() }

    final class Probe: UIView, UIGestureRecognizerDelegate {
        let reference: FeedViewportReference
        private weak var attachedScrollView: UIScrollView?
        var onEdgePan: ((UIGestureRecognizer.State, CGFloat, CGFloat) -> Void)?
        lazy var edgePan: UIPanGestureRecognizer = {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.delegate = self
            pan.maximumNumberOfTouches = 1
            pan.isEnabled = false
            return pan
        }()
        init(reference: FeedViewportReference) {
            self.reference = reference
            super.init(frame: .zero)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
        override func didMoveToWindow() { super.didMoveToWindow(); resolve() }
        override func layoutSubviews() { super.layoutSubviews(); resolve() }
        func resolve() {
            var ancestor = superview
            while let view = ancestor {
                if let scrollView = view as? UIScrollView {
                    reference.scrollView = scrollView
                    if attachedScrollView !== scrollView {
                        detach()
                        attachedScrollView = scrollView
                        scrollView.addGestureRecognizer(edgePan)
                        // A vertical edge drag fails our recognizer immediately. A horizontal
                        // one owns the entire gesture, so the feed never moves underneath it.
                        scrollView.panGestureRecognizer.require(toFail: edgePan)
                    }
                    return
                }
                ancestor = view.superview
            }
        }
        func detach() {
            attachedScrollView?.removeGestureRecognizer(edgePan)
            attachedScrollView = nil
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let scrollView = attachedScrollView else { return false }
            let x = touch.location(in: scrollView).x - scrollView.bounds.minX
            return x >= 0 && x < DrawerEdgePan.activationWidth
        }
        override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView = attachedScrollView else { return false }
            let translation = edgePan.translation(in: scrollView)
            return translation.x > 0 && translation.x > abs(translation.y) * DrawerEdgePan.horizontalBias
        }
        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let scrollView = attachedScrollView else { return }
            onEdgePan?(pan.state, pan.translation(in: scrollView).x, pan.velocity(in: scrollView).x)
        }
    }
}
#endif
