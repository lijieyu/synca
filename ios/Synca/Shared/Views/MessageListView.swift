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
    @State private var categorySwipeIsHorizontal: Bool?
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
    @State private var showDeleteAccountConfirm = false
    @State private var showDeleteAccountSuccess = false
    @State private var deleteAccountErrorMessage: String?
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

    var body: some View {
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
                Text(deleteAccountErrorMessage ?? String(syncaLocalized: "account.delete_failed_message", bundle: .main))
            }
            .sheet(isPresented: $showAccountInfo) {
                AccountSheet(
                    accountEmail: api.currentUserEmail,
                    onRequestDeleteAccount: {
                        showAccountInfo = false
                        showDeleteAccountConfirm = true
                    },
                    onRequestLogout: {
                        showAccountInfo = false
                        showLogoutConfirm = true
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
        .overlay(alignment: .top) { syncStatusOverlay }
        .overlay(alignment: .top) { feedbackToastOverlay }
        .overlay { loadingOverlay }
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
            shouldScrollToBottomAfterInitialLoad = true
            await syncManager.restoreCachedDataIfAvailable()
            
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
        #if os(iOS)
        .onChange(of: syncManager.selectedCategoryId) { _ in
            collapsedRowTarget = nil
            expandedTextIDs.removeAll()
        }
        #endif
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
                    HStack(spacing: 24) {
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
            if let status = accessManager.status {
                DailyQuotaView(status: status).padding(.horizontal, 20).padding(.top, 6)
            }
            categoryToolbar
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
                .simultaneousGesture(DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        if categorySwipeIsHorizontal == nil {
                            categorySwipeIsHorizontal = abs(value.translation.width) > abs(value.translation.height) * 1.5
                        }
                    }
                    .onEnded { value in
                        defer { categorySwipeIsHorizontal = nil }
                        guard categorySwipeIsHorizontal == true else { return }
                        switchCategory(horizontal: value.translation.width, vertical: 0)
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
                    MacCategoryReorderStack(categories: syncManager.categories, spacing: 4, handleOnly: false, disabled: sidebarReordering, onCommit: { ids in
                        sidebarReordering = true
                        _ = await syncManager.reorderCategories(ids: ids)
                        sidebarReordering = false
                    }) { category in
                        sidebarCategory(id: category.id, title: category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name, color: categoryDisplayColor(category.color, hex: category.colorHex), count: todoCount(for: category.id))
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
               let category = syncManager.categories.first(where: { $0.id == id }), !category.isDefault {
                categoryToEdit = category
                showCreateCategory = true
            } else {
                composerFocusRequest += 1
            }
        } label: {
            HStack(spacing: 10) {
                if color == nil { Image(systemName: "square.grid.2x2").font(.system(size: 14, weight: .regular)).frame(width: 16) }
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


            }
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
                if neutral { Image(systemName: "square.grid.2x2").font(.system(size: 13)) }
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
                        ForEach(completed) { message in
                            messageView(for: message, showsSeparator: message.id != (uncompleted.last?.id ?? completed.last?.id),
                                        onTextCollapse: { restoreCollapsedMessage(message, proxy: proxy) })
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
                                messageView(for: message, showsSeparator: message.id != (uncompleted.last?.id ?? completed.last?.id),
                                        onTextCollapse: { restoreCollapsedMessage(message, proxy: proxy) })
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
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
                    scrollTask?.cancel()
                    initialLoadScrollWindowID = UUID()
                    shouldScrollToBottomAfterInitialLoad = false
                }
            }
            // A new category must not inherit the previous list's scroll geometry.
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
        }
        .buttonStyle(.plain)
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
                .frame(width: 24, height: 24)
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

    @MainActor
    private func deleteAccount() async {
        do {
            try await api.deleteAccount()
            showDeleteAccountSuccess = true
        } catch {
            let message = (error as? LocalizedError)?.errorDescription
                ?? String(syncaLocalized: "account.delete_failed_message", bundle: .main)
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
        await syncManager.sendFile(file: pendingFile, categoryId: categoryId)
    }

    private func restoreCollapsedMessage(_ message: SyncaMessage, proxy: ScrollViewProxy) {
        scrollTask?.cancel()
        shouldScrollToBottomAfterInitialLoad = false
        shouldScrollToBottomAfterSend = false
        #if os(iOS)
        // LazyVStack can retain the expanded row's estimated height after a large
        // shrink. Rebuild its geometry; expanded states live above this identity.
        collapsedRowTarget = (syncManager.selectedCategoryId, message.id)
        textLayoutRevision += 1
        #else
        let categoryID = syncManager.selectedCategoryId
        let rowID = "\(message.id)-\(message.isCleared)"
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
        scrollTask?.cancel()
        let categoryId = syncManager.selectedCategoryId
        scrollTask = Task { @MainActor in
            // Coalesce image-load notifications into a single pending scroll.
            try? await Task.sleep(nanoseconds: Timing.scrollCoalescingNanoseconds)
            guard !Task.isCancelled, categoryId == syncManager.selectedCategoryId else { return }
            #if os(macOS)
            proxy.scrollTo("bottom", anchor: .bottom)
            #else
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
    private func messageView(for message: SyncaMessage, showsSeparator: Bool, onTextCollapse: (() -> Void)? = nil) -> some View {
        MessageBubbleView(
            message: message,
            categories: syncManager.categories,
            showsSeparator: showsSeparator,
            isUpdatingCompletion: syncManager.completionUpdates.contains(message.id),
            onEdit: { editingMessage = message },
            onTextCollapse: onTextCollapse,
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
            },
            textExpansion: textExpansionBinding(for: message.id)
        )
        .id("\(message.id)-\(message.isCleared)")
    }

    private func textExpansionBinding(for id: String) -> Binding<Bool>? {
        #if os(iOS)
        return Binding(
            get: { expandedTextIDs.contains(id) },
            set: { if $0 { expandedTextIDs.insert(id) } else { expandedTextIDs.remove(id) } }
        )
        #else
        return nil
        #endif
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
    if PendingFileUpload.supportedExtensions.contains(ext) {
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
                            .id("\(message.id)-\(message.isCleared)")
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
                            .id("\(message.id)-\(message.isCleared)")
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
        guard !isDuplicateCategoryName(trimmed) else {
            showDuplicateNameAlert = true
            return
        }

        isSaving = true
        Task {
            let saved: Bool
            if let category {
                if category.isDefault { saved = false }
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
            .navigationTitle("message_category.new_section")
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
            MacSheetHeader(title: category == nil ? "message_category.new_section" : "message_category.edit_title", onClose: { requestClose() })

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                TextField(String(syncaLocalized: "message_category.name_placeholder", bundle: .main), text: $name)
                    .textFieldStyle(.plain)
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

private struct MessageCategoryManagerSheet: View {
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: SyncaMessageCategory?
    @State private var busy = false
    @State private var failed = false
    @State private var adding = false
    @State private var previewOrder: [String]?
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
    private var customCategories: [SyncaMessageCategory] {
        let categories = syncManager.categories.filter { !$0.isDefault }
        guard let previewOrder else { return categories }
        let lookup = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        return previewOrder.compactMap { lookup[$0] }
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        guard !busy else { return }
        var ids = customCategories.map(\.id)
        ids.move(fromOffsets: source, toOffset: destination)
        guard ids != customCategories.map(\.id) else { return }
        previewOrder = ids
        busy = true
        Task { @MainActor in
            let succeeded = await syncManager.reorderCategories(ids: ids)
            // The authoritative list changes only on success; clearing the preview rolls back failure.
            previewOrder = nil
            busy = false
            if !succeeded { failed = true }
        }
    }

    private var rows: some View {
        List {
            Section {
                ForEach(syncManager.categories.filter(\.isDefault)) { category in
                    categoryRow(category)
                }
                ForEach(customCategories) { category in
                    categoryRow(category)
                        .deleteDisabled(true)
                        .moveDisabled(busy)
                }
                .onMove(perform: reorder)
            }
            Section { addButton }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, .constant(.active))
    }
    #else
    private var rows: some View {
        VStack(spacing: 0) {
            MacCategoryReorderStack(categories: syncManager.categories, spacing: 0, handleOnly: true, disabled: busy, onCommit: { ids in
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
            NavigationStack {
                rows
                    .background(Color.syncaPageBackground)
                    .navigationTitle("message_category.section_title")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done", action: finish).disabled(busy) } }
            }
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

private struct AboutSyncaSheet: View {
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
        NavigationStack {
            sheetContent
                .navigationTitle(Text("message_list.about"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { closeButton }
                }
        }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(contentHeight + 60), .large])
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

                Text(verbatim: "浙ICP备2026013056号-3A")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity)
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

#if os(macOS)
/// Local pointer reordering: the row follows the pointer, siblings make room, and only the final order is saved.
/// No pasteboard drag session is created, so reordering never advertises a copy operation.
private struct MacCategoryRowFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { _, new in new }) }
}
private struct MacCategoryReorderStack<Row: View>: View {
    let categories: [SyncaMessageCategory]
    let spacing: CGFloat
    let handleOnly: Bool
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
                        Color.clear.preference(key: MacCategoryRowFrames.self, value: [category.id: geometry.frame(in: .named(coordinateID))])
                    })
                    .overlay(alignment: .trailing) {
                        if handleOnly && !category.isDefault {
                            Color.clear.frame(width: 36).contentShape(Rectangle()).gesture(drag(category))
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
        .onPreferenceChange(MacCategoryRowFrames.self) { frames = $0 }
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
        .onExitCommand {
            guard !saving, !disabled else { return }
            if gestureInFlight || draggedID != nil {
                gestureCancelled = gestureInFlight
                reset()
            } else {
                onExit?()
            }
        }
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
#endif
