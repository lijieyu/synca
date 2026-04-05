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
    @State private var inputText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showLogoutConfirm = false
    @State private var showClearAllConfirm = false
    @State private var showAboutInfo = false
    @State private var showFeedbackComposer = false
    @State private var showSessionExpired = false
    @State private var inputHeight: CGFloat = 40
    @State private var selectedImageMessage: SyncaMessage? // #NEW: Centralized gallery state
    @State private var shouldScrollToBottomAfterSend = false
    @State private var postSendScrollWindowID = UUID()
    @State private var shouldScrollToBottomAfterInitialLoad = false
    @State private var initialLoadScrollWindowID = UUID()
    @State private var showFeedbackSuccessToast = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                Divider()
                inputBar
            }
            .navigationTitle("")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
#if os(iOS)
                titleToolbarItem
#endif
                actionToolbarItems
            }
            .alert("message_list.clear_all_confirm_title", isPresented: $showClearAllConfirm) {
                Button("common.cancel", role: .cancel) {}
                Button("common.delete", role: .destructive) {
                    Task { await syncManager.clearAll() }
                }
            } message: {
                Text("message_list.clear_all_confirm_message")
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
            .alert("message_list.about", isPresented: $showAboutInfo) {
                Button("message_list.got_it", role: .cancel) {}
            } message: {
                Text(aboutMessage)
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
        .imagePreviewSheet(item: $selectedImageMessage, syncManager: syncManager)
        .task {
            shouldScrollToBottomAfterInitialLoad = true
            await PushTokenManager.shared.uploadCachedTokenIfPossible()
            await purchaseManager.loadProducts()
            await purchaseManager.syncLatestTransactions()
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
        #if os(macOS)
        .background(
            Button("") {
                handlePasteShortcut()
            }
            .keyboardShortcut("v", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        #endif
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

    @ToolbarContentBuilder
    private var actionToolbarItems: some ToolbarContent {
        #if os(iOS)
        ToolbarItem(placement: .topBarTrailing) {
            refreshButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            clearAllButton
        }
        ToolbarItem(placement: .topBarTrailing) {
            settingsMenu
        }
        #else
        ToolbarItem(id: "refresh", placement: .primaryAction) {
            refreshButton
        }
        ToolbarItem(id: "clear", placement: .primaryAction) {
            clearAllButton
        }
        ToolbarItem(id: "menu", placement: .primaryAction) {
            settingsMenu
        }
        #endif
    }

    // MARK: - Subviews

    @ViewBuilder
    private var messageList: some View {
        let completed = syncManager.orderedMessages.filter { $0.isCleared }
        let uncompleted = syncManager.orderedMessages.filter { !$0.isCleared }

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
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: syncManager.orderedMessages)
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
                    guard hasCompletedInitialLoad, !syncManager.orderedMessages.isEmpty else { return }
                    beginInitialLoadScrollWindow()
                    scrollToBottomAfterLayoutSettles(proxy: proxy)
                }
                .onChange(of: syncManager.orderedMessages.count) { _ in
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
                    if syncManager.hasCompletedInitialLoad && !syncManager.orderedMessages.isEmpty {
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
        .disabled(self.syncManager.messages.filter { $0.isCleared }.isEmpty)
    }

    private var settingsMenu: some View {
        Menu {
            Button {
                showFeedbackComposer = true
            } label: {
                Label("message_list.feedback", systemImage: "bubble.left.and.exclamationmark.bubble.right")
            }

            Button {
                #if os(macOS)
                showAboutOnMac()
                #else
                self.showAboutInfo = true
                #endif
            } label: {
                Label("message_list.about", systemImage: "info.circle")
            }

            Button(role: .destructive) {
                self.showLogoutConfirm = true
            } label: {
                Label("message_list.sign_out", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 9, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 22))
            }
            .buttonStyle(.plain)
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
                        await self.syncManager.sendImages(imageDatas)
                    }
                }
            }

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
        .background(.background)
        #endif
    }

    @ViewBuilder
    private var inputField: some View {
        #if os(iOS)
        ZStack(alignment: .leading) {
            PasteAwareTextView(text: $inputText, height: $inputHeight, onImagePaste: { imageData in
                shouldScrollToBottomAfterSend = true
                Task { await syncManager.sendImage(imageData) }
            }, onSubmit: {
                self.submitText()
            })
            .frame(height: max(44, min(inputHeight, 150)))

            if inputText.isEmpty {
                Text("message_list.input_placeholder", bundle: .main)
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
            MacInputTextView(text: $inputText, height: $inputHeight, onPasteImage: { imageData in
                shouldScrollToBottomAfterSend = true
                Task { await syncManager.sendImage(imageData) }
            }, onSubmit: {
                self.submitText()
            })
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(34, min(inputHeight, 104)))
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
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
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
            let result = await syncManager.sendText(text)
            if result != .sent {
                inputText = text
            }
        }
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
    
    private var aboutMessage: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(format: String(localized: "message_list.about_message", bundle: .main), version, build)
    }

    #if os(macOS)
    private func handlePasteShortcut() {
        let pb = NSPasteboard.general

        if let rawPngData = pb.data(forType: .png) {
            shouldScrollToBottomAfterSend = true
            Task { await syncManager.sendImage(rawPngData) }
            return
        }
        if let rawJpegData = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            shouldScrollToBottomAfterSend = true
            Task { await syncManager.sendImage(rawJpegData) }
            return
        }
        if let rawHeicData = pb.data(forType: NSPasteboard.PasteboardType("public.heic")) {
            shouldScrollToBottomAfterSend = true
            Task { await syncManager.sendImage(rawHeicData) }
            return
        }
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
           let tiffData = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let pngData = bitmap.representation(using: .png, properties: [:]) {
            shouldScrollToBottomAfterSend = true
            Task { await syncManager.sendImage(pngData) }
            return
        }

        NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
    }

    private func showAboutOnMac() {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = String(localized: "message_list.about", bundle: .main)
        alert.informativeText = aboutMessage
        alert.addButton(withTitle: String(localized: "message_list.got_it", bundle: .main))
        alert.runModal()
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
            onClear: {
                Task { await syncManager.clearMessage(message.id) }
            },
            onDelete: {
                Task { await syncManager.deleteMessage(message.id) }
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
}

private extension Notification.Name {
    static let syncaScrollToBottomAfterImageLoad = Notification.Name("syncaScrollToBottomAfterImageLoad")
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
