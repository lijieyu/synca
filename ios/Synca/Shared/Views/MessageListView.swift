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
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showLogoutConfirm = false

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
                    .onChange(of: syncManager.messages.count) { _, _ in
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
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    clearAllButton
                }
                ToolbarItem(placement: .topBarTrailing) {
                    settingsMenu
                }
            }
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    clearAllButton
                }
                ToolbarItem(placement: .automatic) {
                    settingsMenu
                }
            }
            #endif
            .alert("确认退出", isPresented: $showLogoutConfirm) {
                Button("取消", role: .cancel) {}
                Button("退出", role: .destructive) {
                    syncManager.reset()
                    AuthService.shared.signOut()
                }
            } message: {
                Text("退出后需要重新登录")
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

            // Update badge
            updateBadge()
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
                Task { await syncManager.clearAll() }
            }
            .font(.subheadline)
        }
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
            // Photo picker
            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 22))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self) {
                        await compressAndSendImage(data)
                    }
                    selectedPhotoItem = nil
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

    private func compressAndSendImage(_ data: Data) async {
        #if canImport(UIKit)
        if let uiImage = UIImage(data: data),
           let jpegData = uiImage.jpegData(compressionQuality: 0.7) {
            await syncManager.sendImage(jpegData)
        }
        #elseif canImport(AppKit)
        if let nsImage = NSImage(data: data),
           let tiffData = nsImage.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiffData),
           let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            await syncManager.sendImage(jpegData)
        }
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
