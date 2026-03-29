import SwiftUI
import PhotosUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

struct MessageListView: View {
    @EnvironmentObject var syncManager: SyncManager
    @EnvironmentObject var api: APIClient
    @State private var inputText = ""
    @State private var selectedPhotoItems: [PhotosPickerItem] = []  // #2: 多选图片
    @State private var showLogoutConfirm = false
    @State private var showClearAllConfirm = false  // #1: 清理全部二次确认
    @State private var showSessionExpired = false   // #7: 登录过期弹窗

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Message list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(syncManager.messages) { message in
                                MessageBubbleView(message: message) {
                                    Task { await syncManager.clearMessage(message.id) }
                                }
                                .id(message.id)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 8)

                        // Invisible anchor for scrolling
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    #if os(iOS)
                    .scrollDismissesKeyboard(.interactively)  // #4: 拖动收起键盘
                    .refreshable {  // #5: iOS 下拉刷新
                        await syncManager.refresh()
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
                    // #5: 叠加右下角滚到底部按钮
                    .overlay(alignment: .bottomTrailing) {
                        scrollToBottomButton(proxy: proxy)
                    }
                }

                Divider()

                // Input bar
                inputBar
            }
            #if os(iOS)
            .navigationTitle("Synca")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        clearAllButton
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        refreshButton  // #5: 头部刷新按钮
                        settingsMenu
                    }
                }
            }
            #else
            .navigationTitle("Synca")
            .toolbar(.hidden)
            .safeAreaInset(edge: .top) {
                HStack {
                    clearAllButton
                    Spacer()
                    Text("Synca")
                        .font(.headline)
                    Spacer()
                    refreshButton  // #5: 头部刷新按钮
                    settingsMenu
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            #endif
            // #1: 清理全部二次确认
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
            // #7: 登录过期弹窗
            .alert("登录已过期", isPresented: $showSessionExpired) {
                Button("重新登录") {
                    syncManager.reset()
                }
            } message: {
                Text("请重新登录以继续使用")
            }
        }
        .overlay {
            if syncManager.isLoading {
                ProgressView("加载中...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .task {
            await syncManager.fullSync()
            syncManager.startPolling()
            updateBadge()
        }
        // #7: 监听 session 过期
        .onChange(of: syncManager.sessionExpired) { expired in
            if expired {
                showSessionExpired = true
            }
        }
        #if os(iOS)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            Task { await syncManager.incrementalSync() }
        }
        #elseif os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await syncManager.incrementalSync() }
        }
        #endif
        .onDisappear {
            syncManager.stopPolling()
        }
    }

    // MARK: - Toolbar Items

    @ViewBuilder
    private var clearAllButton: some View {
        if syncManager.unclearedCount > 0 {
            Button("清理全部") {
                showClearAllConfirm = true  // #1: 二次确认
            }
            .font(.subheadline)
        }
    }

    // #5: 刷新按钮
    private var refreshButton: some View {
        Button {
            Task { await syncManager.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15))
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
    }

    // #5: 滚动到底部按钮
    @ViewBuilder
    private func scrollToBottomButton(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.3)) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        } label: {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.white, Color.accentColor)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 16)
        .padding(.bottom, 12)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            // #2: 多选图片
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
                            if let compressed = compressImageData(data) {
                                imageDatas.append(compressed)
                            }
                        }
                    }
                    selectedPhotoItems = []
                    if !imageDatas.isEmpty {
                        await syncManager.sendImages(imageDatas)
                    }
                }
            }

            // Text input
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
                        let text = inputText
                        inputText = ""
                        Task { await syncManager.sendText(text) }
                    }
                }
                #endif

            // Send button
            Button {
                let text = inputText
                inputText = ""
                Task { await syncManager.sendText(text) }
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

    private func compressImageData(_ data: Data) -> Data? {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data) {
            return uiImage.jpegData(compressionQuality: 0.7)
        }
        return nil
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data),
           let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData) {
            return bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])
        }
        return nil
        #endif
    }

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
}
