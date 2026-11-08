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
            .sheet(isPresented: $showCategoryManager) {
                MessageCategoryManagerSheet()
                    .environmentObject(syncManager)
                    .syncaPreferences()
                    #if os(iOS)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    #endif
            }
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
                    .padding(8).frame(width: 224)
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
            #if os(iOS)
            Divider().frame(maxWidth: 760)
            #endif
            inputBar.frame(maxWidth: 800)
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
            }.padding(.horizontal, 12).padding(.top, 48).padding(.bottom, 24)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    sidebarCategory(id: syncManager.allCategoryPseudoId, title: String(syncaLocalized: "message_list.all_records"), color: nil, count: allTodoCount)
                    Text("message_list.my_categories").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.top, 20).padding(.bottom, 7)
                    ForEach(syncManager.categories) { category in
                        sidebarCategory(id: category.id, title: category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name, color: categoryAccentColor(for: category.color), count: todoCount(for: category.id))
                    }
                    Button { categoryToEdit = nil; showCreateCategory = true } label: {
                        Label("message_category.add_action", systemImage: "plus")
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            Button { showManagementMenu.toggle() } label: {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 7) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 16)).foregroundStyle(.secondary).accessibilityHidden(true)
                        if let status = accessManager.status {
                            Text(planName(status)).font(.subheadline.weight(.medium))
                        } else {
                            Text("account.section_title").font(.subheadline.weight(.medium))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.up").font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(api.currentUserEmail ?? String(syncaLocalized: "account.section_title"))
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                        .help(api.currentUserEmail ?? String(syncaLocalized: "account.section_title"))
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
            .padding(.bottom, 14)
        }
        .padding(.horizontal, 12).frame(width: 220)
        .background(Color(nsColor: .controlBackgroundColor))
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
                if color == nil { Image(systemName: "tray").frame(width: 16) }
                Text(title).lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if count > 0 { Text(count, format: .number).font(.caption2.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((color ?? Color.syncaPurple).opacity(selected ? 0.24 : 0.12), in: Capsule()) }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .foregroundStyle(Color.primary)
            .background((color ?? Color.syncaPurple).opacity(selected ? 0.22 : 0.08), in: RoundedRectangle(cornerRadius: 8))
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
        if !status.isUnlimited { return String(syncaLocalized: "access.free_title") }
        if status.unlimitedSource == "lifetime" { return String(syncaLocalized: "access.purchased_lifetime") }
        if status.storeProductId?.hasSuffix("monthly") == true { return String(syncaLocalized: "access.purchased_monthly") }
        if status.storeProductId?.hasSuffix("yearly") == true { return String(syncaLocalized: "access.purchased_yearly") }
        return String(syncaLocalized: "access.status_unlimited")
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
                        showAccountInfo = true
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
                        color: .secondary.opacity(0.16),
                        isSelected: syncManager.selectedCategoryId == syncManager.allCategoryPseudoId,
                        badgeCount: allTodoCount
                    ) {
                        syncManager.selectCategory(syncManager.allCategoryPseudoId)
                    }
                    .id(syncManager.allCategoryPseudoId)

                    ForEach(syncManager.categories) { category in
                        categoryChip(
                            title: category.isDefault ? String(syncaLocalized: "message_category.default_badge", bundle: .main) : category.name,
                            color: categoryAccentColor(for: category.color),
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

    private func categoryChip(title: String, color: Color, isSelected: Bool, badgeCount: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(isSelected ? .semibold : .regular))
                if badgeCount > 0 { Text(badgeCount, format: .number).font(.caption2.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(color.opacity(isSelected ? 0.25 : 0.14), in: Capsule()) }
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(color.opacity(isSelected ? 0.24 : 0.10), in: Capsule())
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
            ProgressView("message_list.loading")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if completed.isEmpty && uncompleted.isEmpty {
            emptyStateView
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(completed) { message in
                            messageView(for: message, showsSeparator: message.id != (uncompleted.last?.id ?? completed.last?.id))
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
                                messageView(for: message, showsSeparator: message.id != (uncompleted.last?.id ?? completed.last?.id))
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .frame(maxWidth: 760)
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
                    if syncManager.hasCompletedInitialLoad && !filteredMessages.isEmpty {
                        beginInitialLoadScrollWindow()
                        scrollToBottomAfterLayoutSettles(proxy: proxy)
                    }
                }
                .onDisappear {
                    scrollTask?.cancel()
                    initialLoadScrollWindowID = UUID()
                    shouldScrollToBottomAfterInitialLoad = false
                }
            }
            // A new category must not inherit the previous list's scroll geometry.
            .id(syncManager.selectedCategoryId ?? syncManager.allCategoryPseudoId)
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
            Image("BroomOutline").resizable().frame(width: 18, height: 18)
                .foregroundStyle(.secondary)
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
        Button { showManagementMenu = false; showFeedbackComposer = true } label: { Label("message_list.feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right") }
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
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.bar)
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
            MacInputTextView(text: $inputText, height: $inputHeight, isSending: syncManager.isSending, focusRequest: composerFocusRequest, onPasteImage: { imageData in
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
    private func messageView(for message: SyncaMessage, showsSeparator: Bool) -> some View {
        MessageBubbleView(
            message: message,
            categories: syncManager.categories,
            showsSeparator: showsSeparator,
            isUpdatingCompletion: syncManager.completionUpdates.contains(message.id),
            onEdit: { editingMessage = message },
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

    init(category: SyncaMessageCategory? = nil, onManageCategories: @escaping () -> Void) {
        self.category = category
        self.onManageCategories = onManageCategories
        _name = State(initialValue: category?.name ?? "")
        _color = State(initialValue: category?.color ?? .sky)
    }

    @State private var name = ""
    @State private var color: MessageCategoryColor = .sky
    @State private var showDuplicateNameAlert = false
    @State private var isSaving = false
    @State private var showSaveError = false
    @State private var showDiscardConfirm = false
    @State private var pendingManage = false

    private var hasChanges: Bool {
        name != (category?.name ?? "") || color != (category?.color ?? .sky)
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
                else { saved = await syncManager.updateCategory(id: category.id, name: trimmed, color: color) }
            } else {
                saved = await syncManager.createCategory(name: trimmed, color: color) != nil
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
            .scrollContentBackground(.hidden)
            .background(Color.syncaPageBackground)
            .navigationTitle("message_category.new_section")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { requestClose() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(category == nil ? "message_category.add_action" : "common.save") {
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
            .padding(20)

            Divider()

            HStack(spacing: 12) {
                Button {
                    requestClose(manage: true)
                } label: {
                    Text("message_list.manage_categories", bundle: .main)
                        .font(.callout.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)

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
        .confirmationDialog("message_edit.discard_title", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("message_edit.discard", role: .destructive) { finishClose() }
            Button("common.cancel", role: .cancel) {}
        }
        .alert("message_category.save_failed_title", isPresented: $showSaveError) {
            Button("common.ok", role: .cancel) {}
        } message: { Text("message_category.save_failed_message") }
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

    @State private var contentHeight: CGFloat = 200
    @State private var draftRows: [CategoryDraftRow] = []
    @State private var initialDraftRows: [CategoryDraftRow] = []
    @State private var isSaving = false
    @State private var showDiscardConfirm = false
    @State private var showSaveError = false

    private var hasChanges: Bool { draftRows != initialDraftRows }

    #if os(macOS)
    private var preferredSheetHeight: CGFloat {
        let available = (NSScreen.main?.visibleFrame.height ?? 860) - 100
        return min(max(280, contentHeight + 125), available)
    }
    #endif

    private func requestClose() {
        guard !isSaving else { return }
        if hasChanges { showDiscardConfirm = true } else { dismiss() }
    }

    @State private var pendingDeleteRow: CategoryDraftRow?
    @State private var validationAlert: CategoryValidationAlert?
    @State private var editorRow: CategoryDraftRow?
    @State private var isReordering = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
        initialDraftRows = draftRows
    }

    private func addDraftRow() {
        editorRow = CategoryDraftRow(localId: "new-\(UUID().uuidString)", categoryId: nil, name: "", color: .sky)
    }

    private func applyEditorRow(_ row: CategoryDraftRow) {
        if let index = draftRows.firstIndex(where: { $0.id == row.id }) {
            draftRows[index] = row
        } else {
            draftRows.append(row)
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
        guard !isSaving, validateDraftRows() else { return }
        isSaving = true

        let rows = draftRows
        let originalCategories = editableCategories
        let originalById = Dictionary(uniqueKeysWithValues: originalCategories.map { ($0.id, $0) })
        let keptIds = Set(rows.compactMap(\.categoryId))

        Task {
            defer { isSaving = false }
            for category in originalCategories where !keptIds.contains(category.id) {
                guard await syncManager.deleteCategory(id: category.id) else { showSaveError = true; return }
            }

            var orderedCategoryIds: [String] = []
            for row in rows {
                let name = row.name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let categoryId = row.categoryId {
                    guard let original = originalById[categoryId] else { continue }
                    let updatedName = name == original.name ? nil : name
                    let updatedColor = row.color == original.color ? nil : row.color
                    if updatedName != nil || updatedColor != nil {
                        guard await syncManager.updateCategory(id: categoryId, name: updatedName, color: updatedColor) else { showSaveError = true; return }
                    }
                    orderedCategoryIds.append(categoryId)
                } else {
                    if let category = await syncManager.createCategory(name: name, color: row.color) {
                        orderedCategoryIds.append(category.id)
                        if let index = draftRows.firstIndex(where: { $0.localId == row.localId }) {
                            draftRows[index] = CategoryDraftRow(localId: row.localId, categoryId: category.id, name: row.name, color: row.color)
                        }
                    } else { showSaveError = true; return }
                }
            }

            guard await syncManager.reorderCategories(ids: orderedCategoryIds) else { showSaveError = true; return }
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
        .sheet(item: $editorRow) { row in
            CategoryDraftEditorSheet(
                initialRow: row,
                existingNames: draftRows.filter { $0.id != row.id }.map(\.name),
                onSave: applyEditorRow
            )
            .syncaPreferences()
        }
        .disabled(isSaving)
        .interactiveDismissDisabled(hasChanges || isSaving)
        .confirmationDialog("message_edit.discard_title", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("message_edit.discard", role: .destructive) { dismiss() }
            Button("common.cancel", role: .cancel) {}
        }
        .alert("message_category.save_failed_title", isPresented: $showSaveError) {
            Button("common.ok", role: .cancel) {}
        } message: { Text("message_category.save_failed_message") }
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
        .frame(width: min(480, (NSScreen.main?.visibleFrame.width ?? 580) - 80))
        .frame(minHeight: preferredSheetHeight, idealHeight: preferredSheetHeight, maxHeight: preferredSheetHeight)
        .background(MacSheetSizeObserver(contentSize: NSSize(
            width: min(480, (NSScreen.main?.visibleFrame.width ?? 580) - 80),
            height: preferredSheetHeight
        )))
        #endif
    }

    private var categoryList: some View {
        VStack(spacing: 12) {
            HStack {
                Text("message_category.my_categories")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(isReordering ? "message_category.finish_reordering" : "message_category.reorder") {
                    isReordering.toggle()
                }
                .font(.subheadline)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .frame(minHeight: 44)
                .disabled(draftRows.count < 2 && !isReordering)
            }
            VStack(spacing: 0) {
                ForEach(Array(draftRows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.horizontal, 12) }
                    CategoryDraftListRow(
                        row: row,
                        isReordering: isReordering,
                        canMoveUp: index > 0,
                        canMoveDown: index < draftRows.count - 1,
                        onMoveUp: { moveDraftRow(from: index, to: index - 1) },
                        onMoveDown: { moveDraftRow(from: index, to: index + 1) },
                        onEdit: { editorRow = row },
                        onDelete: { pendingDeleteRow = row }
                    )
                }
            }
            .background(Color.syncaCardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.syncaCardBorder, lineWidth: draftRows.isEmpty ? 0 : 1))
            Button(action: addDraftRow) {
                Label("message_category.add_action", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: SheetContentHeightKey.self, value: proxy.size.height)
        })
    }

    #if os(iOS)
    private var iosBody: some View {
        NavigationStack {
            ScrollView { categoryList }
                .background(Color.syncaPageBackground)
                .navigationTitle("message_category.section_title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.cancel") { requestClose() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.save") { saveDraftRows() }.fontWeight(.semibold)
                    }
                }
        }
        .onPreferenceChange(SheetContentHeightKey.self) { contentHeight = $0 }
        .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(max(280, contentHeight + 68)), .large])
        .presentationDragIndicator(.visible)
    }
    #else
    private var macOSBody: some View {
        VStack(spacing: 0) {
            MacSheetHeader(title: "message_category.section_title", onClose: { requestClose() })
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
            Divider()
            ScrollView { categoryList }
                .onPreferenceChange(SheetContentHeightKey.self) { height in
                    guard height > 0, abs(contentHeight - height) > 1 else { return }
                    contentHeight = height
                }
                .background(Color.syncaPageBackground.opacity(0.55))
            Divider()
            HStack(spacing: 8) {
                Spacer()
                Button("common.cancel", role: .cancel) { requestClose() }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.primary)
                    .keyboardShortcut(.cancelAction)
                Button("common.save") { saveDraftRows() }
                    .buttonStyle(MacPrimaryActionButtonStyle())
                    .tint(.syncaPurple)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
        }
    }
    #endif
}

private func categoryColorAccent(_ color: MessageCategoryColor) -> Color {
    switch color {
    case .sky: return .blue
    case .mint: return .green
    case .amber: return .orange
    case .coral: return .red
    case .violet: return .purple
    case .slate: return .secondary
    case .rose: return .pink
    case .ocean: return .cyan
    }
}

private struct CategoryDraftListRow: View {
    let row: CategoryDraftRow
    let isReordering: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(row.name)
                .font(.body.weight(.medium))
                .foregroundStyle(categoryColorAccent(row.color))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(categoryColorAccent(row.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if isReordering {
                iconButton("arrow.up", label: "message_category.move_up", action: onMoveUp)
                    .disabled(!canMoveUp)
                iconButton("arrow.down", label: "message_category.move_down", action: onMoveDown)
                    .disabled(!canMoveDown)
            } else {
                iconButton("pencil", label: "message_category.edit_title", action: onEdit)
                Menu {
                    Button("message_category.edit_title", action: onEdit)
                    Button("message_category.delete_action", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .menuStyle(.borderlessButton)
                #if os(macOS)
                .menuIndicator(.hidden)
                #endif
                .fixedSize()
                .accessibilityLabel(Text("message_category.more"))
                .accessibilityValue(row.name)
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func iconButton(_ icon: String, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).frame(width: 44, height: 44).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label))
            .accessibilityValue(row.name)
    }
}

private struct CategoryDraftEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var row: CategoryDraftRow
    @State private var showDuplicate = false
    @FocusState private var nameFocused: Bool
    let existingNames: [String]
    let onSave: (CategoryDraftRow) -> Void
    private let isNew: Bool

    init(initialRow: CategoryDraftRow, existingNames: [String], onSave: @escaping (CategoryDraftRow) -> Void) {
        _row = State(initialValue: initialRow)
        self.existingNames = existingNames
        self.onSave = onSave
        isNew = initialRow.name.isEmpty
    }

    private var title: LocalizedStringKey { isNew ? "message_category.add_action" : "message_category.edit_title" }
    private var trimmedName: String { row.name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        guard !existingNames.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase == trimmedName.localizedLowercase }) else {
            showDuplicate = true
            return
        }
        row.name = trimmedName
        onSave(row)
        dismiss()
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("message_category.name_placeholder").font(.subheadline).foregroundStyle(.secondary)
            TextField("message_category.name_placeholder", text: $row.name)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color.syncaPageBackground, in: RoundedRectangle(cornerRadius: 8))
                .focused($nameFocused)
                .accessibilityLabel(Text("message_category.name_placeholder"))
                .onSubmit(save)
            Text("message_category.color_label").font(.subheadline).foregroundStyle(.secondary).padding(.top, 4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 12) {
                ForEach(MessageCategoryColor.allCases) { color in
                    Button { row.color = color } label: {
                        Circle().fill(categoryColorAccent(color))
                            .frame(width: 28, height: 28)
                            .overlay {
                                if row.color == color {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(verbatim: AppLocalization.string("message_category.color.\(color.rawValue)")))
                    .accessibilityAddTraits(row.color == color ? .isSelected : [])
                }
            }
        }
        .padding(20)
    }

    var body: some View {
        Group {
            #if os(iOS)
            NavigationStack {
                ScrollView { fields }
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(isNew ? "message_category.add_action" : "common.save", action: save).disabled(trimmedName.isEmpty)
                        }
                    }
            }
            .presentationDetents(dynamicTypeSize.isAccessibilitySize ? [.large] : [.height(340), .large])
            #else
            VStack(spacing: 0) {
                MacSheetHeader(title: title, onClose: { dismiss() })
                Divider()
                fields
                Divider()
                HStack {
                    Spacer()
                    Button("common.cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                    Button(isNew ? "message_category.add_action" : "common.save", action: save)
                        .buttonStyle(MacPrimaryActionButtonStyle())
                        .disabled(trimmedName.isEmpty)
                }.padding(20)
            }
            .frame(width: 420)
            .fixedSize(horizontal: false, vertical: true)
            #endif
        }
        .alert("message_category.duplicate_title", isPresented: $showDuplicate) {
            Button("common.ok", role: .cancel) {}
        } message: { Text("message_category.duplicate_message") }
        .onAppear { nameFocused = true }
    }
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
                HStack(spacing: 12) {
                    aboutLink("access.privacy_policy_link_title", destination: AppLinks.privacyPolicyURL)
                    aboutLink("message_list.support", destination: AppLinks.supportURL)
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
private struct ManagementMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10).padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.primary.opacity(0.08) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6))
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
