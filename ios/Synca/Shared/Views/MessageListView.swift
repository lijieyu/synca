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
    @State private var inputText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var showLogoutConfirm = false
    @State private var showClearAllConfirm = false
    @State private var showSessionExpired = false
    @State private var selectedImageMessage: SyncaMessage? // #NEW: Centralized gallery state

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(syncManager.messages) { message in
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
                                    }
                                )
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    #if os(iOS)
                    .scrollDismissesKeyboard(.onDrag)
                    .refreshable {
                        await syncManager.refresh()
                    }
                    .onTapGesture {
                        hideKeyboard()
                    }
                    #endif
                    .onChange(of: syncManager.messages.count) { _ in
                        withAnimation(.easeOut(duration: 0.3)) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo("bottom", anchor: .bottom)
                        }
                    }
                } // End ScrollViewReader

                Divider()

                // Input bar
                inputBar
            }
            .navigationTitle("Synca")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // Trailing group for all actions (#1)
                ToolbarItemGroup(placement: .primaryAction) {
                    refreshButton
                    clearAllButton
                    settingsMenu
                }
            }
            .alert("确认清理全部", isPresented: $showClearAllConfirm) {
                Button("取消", role: .cancel) {}
                Button("清理全部", role: .destructive) {
                    Task { await syncManager.clearAll() }
                }
            } message: {
                Text("将清理所有 \(syncManager.unclearedCount) 条未处理消息")
            }
            .alert("确认退出", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) {
                    syncManager.reset()
                    AuthService.shared.signOut()
                }
            } message: {
                Text("退出后需要重新登录")
            }
            .alert("登录已过期", isPresented: $showSessionExpired) {
                Button("重新登录") {
                    syncManager.reset()
                }
            } message: {
                Text("请重新登录以继续使用")
            }
        }
        .overlay(alignment: .top) {
            Group {
                if case .success = syncManager.syncStatus {
                    Label("同步成功", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                } else if case .error(let msg) = syncManager.syncStatus {
                    Label("同步失败", systemImage: "xmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 3)
                        .padding(.top, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: syncManager.syncStatus)
        }
        .overlay {
            if syncManager.isLoading && syncManager.messages.isEmpty {
                ProgressView("加载中...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        #if os(iOS)
        .fullScreenCover(item: $selectedImageMessage) { msg in
            let allImages = syncManager.imageMessages
            let initialIndex = allImages.firstIndex(where: { $0.id == msg.id }) ?? 0
            ImagePreviewView(messages: allImages, initialIndex: initialIndex) { deletedMessageId in
                // If a message was deleted from inside the preview
                Task { await syncManager.deleteMessage(deletedMessageId) }
            }
        }
        #else
        .sheet(item: $selectedImageMessage) { msg in
            let allImages = syncManager.imageMessages
            let initialIndex = allImages.firstIndex(where: { $0.id == msg.id }) ?? 0
            ImagePreviewView(messages: allImages, initialIndex: initialIndex) { deletedMessageId in
                Task { await syncManager.deleteMessage(deletedMessageId) }
            }
            .frame(minWidth: 800, minHeight: 600)
        }
        #endif
        .task {
            await syncManager.fullSync(manual: true)
            syncManager.startPolling()
            updateBadge()
        }
        .onChange(of: syncManager.unclearedCount) { _ in
            updateBadge()
        }
        .onChange(of: syncManager.sessionExpired) { expired in
            if expired {
                showSessionExpired = true
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await syncManager.incrementalSync(manual: false) }
        }
        #elseif os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await syncManager.incrementalSync(manual: false) }
        }
        #endif
        .onDisappear {
            syncManager.stopPolling()
        }
        #if os(macOS)
        .background(
            Button("") {
                handlePaste()
            }
            .keyboardShortcut("v", modifiers: .command)
            .opacity(0)
            .allowsHitTesting(false)
        )
        #endif
    }

    // MARK: - Toolbar Items

    @ViewBuilder
    private var clearAllButton: some View {
        Button {
            showClearAllConfirm = true
        } label: {
            Image(systemName: "trash")
        }
        .disabled(syncManager.unclearedCount == 0)
    }

    private var refreshButton: some View {
        Button {
            Task { await syncManager.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(syncManager.isRefreshing)
    }

    private var settingsMenu: some View {
        Menu {
            Button(role: .destructive) {
                showLogoutConfirm = true
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuIndicator(.hidden)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 9, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .onChange(of: selectedPhotoItems) { items in
                guard !items.isEmpty else { return }
                Task {
                    var imageDatas: [Data] = []
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            // Phase 29: NEVER re-compress original files (PNG, HEIC, JPEG).
                            // Byte-for-byte retention of metadata and transparency.
                            imageDatas.append(data)
                        }
                    }
                    selectedPhotoItems = []
                    if !imageDatas.isEmpty {
                        await syncManager.sendImages(imageDatas)
                    }
                }
            }

            TextField("输入灵感...", text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                #if os(iOS)
                .background(Color(.systemGray6))
                #else
                .background(Color(.controlBackgroundColor))
                #endif
                .clipShape(RoundedRectangle(cornerRadius: 20))
                #if os(macOS)
                .onSubmit {
                    if canSend {
                        submitText()
                    }
                }
                #endif

            Button {
                submitText()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(canSend ? Color.accentColor : Color.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            #if os(macOS)
            .keyboardShortcut(.return, modifiers: .command)
            #endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        #if os(iOS)
        .background(.bar)
        #else
        .background(.background)
        #endif
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !syncManager.isSending
    }

    private func submitText() {
        let text = inputText
        inputText = ""
        Task { await syncManager.sendText(text) }
    }

    // [Removed] compressImageData: No longer needed. All bytes are now handled losslessly.

    private func updateBadge() {
        let count = syncManager.unclearedCount
        #if os(iOS)
        UNUserNotificationCenter.current().setBadgeCount(count) { _ in }
        #elseif os(macOS)
        if count > 0 {
            NSApp.dockTile.badgeLabel = "\(count)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
        #endif
    }
    
    #if os(macOS)
    private func handlePaste() {
        let pb = NSPasteboard.general
        
        // 1. Check for raw Image Data Streams (Highest Priority: Zero Quality Loss)
        // If the user copied an actual image file or web image, we can directly snatch
        // the raw encoded bytes WITHOUT decoding to an NSImage and re-compressing it.
        if let rawPngData = pb.data(forType: .png) {
            Task { await syncManager.sendImage(rawPngData) }
            return
        }
        if let rawJpegData = pb.data(forType: NSPasteboard.PasteboardType("public.jpeg")) {
            Task { await syncManager.sendImage(rawJpegData) }
            return
        }
        if let rawHeicData = pb.data(forType: NSPasteboard.PasteboardType("public.heic")) {
            Task { await syncManager.sendImage(rawHeicData) }
            return
        }
        
        // 2. Check for Memory Bitmaps (Fallback: e.g. partial screen captures)
        // Screenshots dump raw TIFF uncompressed bytes into the clipboard.
        if let image = pb.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage {
            // Encode purely lossless to PNG to prevent screenshot edge blurring. (No 0.7 JPEG)
            if let tiffData = image.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let losslessCompressed = bitmap.representation(using: .png, properties: [:]) {
                Task { await syncManager.sendImage(losslessCompressed) }
                return
            }
        }
        
        // 2. Check for Text (normal paste)
        if let text = pb.string(forType: .string) {
            inputText += text
        }
    }
    #endif

    #if os(iOS)
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    #endif
}
