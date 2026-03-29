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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Status Tip (#5)
                syncStatusTip

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
                    .scrollDismissesKeyboard(.interactively)
                    .refreshable {
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
                }

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
        .overlay {
            if syncManager.isLoading && syncManager.messages.isEmpty {
                ProgressView("加载中...")
                    .padding()
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
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
        .onPasteCommand(of: [.image]) { providers in
            for provider in providers {
                _ = provider.loadDataRepresentation(for: .image) { data, error in
                    if let data = data {
                        Task { @MainActor in
                            if let compressed = compressImageData(data) {
                                await syncManager.sendImage(compressed)
                            }
                        }
                    }
                }
            }
        }
        #endif
    }

    // MARK: - Header Tip
    
    @ViewBuilder
    private var syncStatusTip: some View {
        Group {
            switch syncManager.syncStatus {
            case .syncing:
                Text("正在同步...")
            case .success:
                Text("同步成功")
                    .foregroundStyle(.green)
            case .error:
                Text("同步失败")
                    .foregroundStyle(.red)
            case .idle:
                if let lastDate = syncManager.lastRefreshDate {
                    Text("上次同步: \(lastDate.formatted(date: .omitted, time: .shortened))")
                } else {
                    EmptyView()
                }
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.05))
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

    private func compressImageData(_ data: Data) -> Data? {
        #if os(iOS)
        if let uiImage = UIImage(data: data) {
            return uiImage.jpegData(compressionQuality: 0.7)
        }
        return nil
        #elseif os(macOS)
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
