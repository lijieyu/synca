import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Search owns its index and scope so dismissing it cannot mutate the feed.
struct MessageSearchView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.dismiss) private var dismiss
    let currentCategoryID: String?
    let onSelect: (String) -> Bool
    @State private var query = ""
    @State private var currentOnly = false
    @State private var results: [MessageSearchResult] = []
    @State private var searching = false
    @State private var unavailable = false
    @State private var revision = 0
    @State private var index = MessageSearchIndex()
    @FocusState private var searchFocused: Bool

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacSheetHeader(title: "search.title")
            Divider()
            content
        }
        .frame(width: 560, height: min(600, max(320, 170 + CGFloat(results.count) * 92)))
        #else
        NavigationStack {
            content
                .navigationTitle(Text("search.title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("common.cancel") { dismiss() } } }
        }
        #endif
    }

    private var content: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField("search.placeholder", text: $query)
                    .textFieldStyle(.plain).focused($searchFocused)
                    .accessibilityIdentifier("search-query")
                    #if os(iOS)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    #endif
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).accessibilityLabel(Text("search.clear"))
                }
            }
            .padding(12).background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            if currentCategoryID != nil {
                Picker("search.scope", selection: $currentOnly) {
                    Text("search.all").tag(false)
                    Text(currentCategoryName).tag(true)
                }.pickerStyle(.segmented).labelsHidden()
            }
            if unavailable { Text("search.unavailable").font(.callout).foregroundStyle(.secondary) }
            if searching {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                emptyState("search.prompt", symbol: "magnifyingglass")
            } else if results.isEmpty {
                emptyState("search.empty", symbol: "doc.text.magnifyingglass")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            Button {
                                unavailable = !onSelect(result.id)
                                if unavailable {
                                    let announcement = String(syncaLocalized: "search.unavailable")
                                    #if os(iOS)
                                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                                    UIAccessibility.post(notification: .announcement, argument: announcement)
                                    #else
                                    NSAccessibility.post(element: NSApp.keyWindow as Any? ?? NSApp as Any,
                                        notification: .announcementRequested,
                                        userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue])
                                    #endif
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(result.excerpt).font(.body).foregroundStyle(.primary).lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let filename = result.message.fileName, !filename.isEmpty, filename != result.excerpt {
                                        Label(filename, systemImage: "doc").font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    HStack(spacing: 8) {
                                        if result.message.isCleared { Image(systemName: "checkmark.circle").accessibilityLabel(Text("search.completed")) }
                                        Text(categoryName(result.message))
                                        Spacer(minLength: 4)
                                        Text(String(result.message.createdAt.prefix(10))).monospacedDigit()
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 14).padding(.horizontal, 6).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityHint(Text("search.open_hint"))
                                .accessibilityIdentifier("search-result-\(result.id)")
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(20)
        .background(Color.syncaPageBackground)
        .task { searchFocused = true }
        .onReceive(syncManager.$messages) { _ in revision += 1 }
        .task(id: SearchRequest(query: query, currentOnly: currentOnly, revision: revision)) {
            searching = true
            unavailable = false
            let snapshot = syncManager.messages
            let matches = await index.search(snapshot, query: query, categoryID: currentOnly ? currentCategoryID : nil)
            guard !Task.isCancelled else { return }
            results = matches
            searching = false
        }
    }

    private var currentCategoryName: String {
        guard let category = syncManager.categories.first(where: { $0.id == currentCategoryID }) else {
            return String(syncaLocalized: "search.current")
        }
        return category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name
    }

    private func categoryName(_ message: SyncaMessage) -> String {
        if let category = syncManager.categories.first(where: { $0.id == message.categoryId }) {
            return category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name
        }
        return message.categoryIsDefault == true ? String(syncaLocalized: "message_category.default_badge")
            : message.categoryName ?? String(syncaLocalized: "message_category.default_badge")
    }

    private func emptyState(_ title: LocalizedStringKey, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.largeTitle).accessibilityHidden(true)
            Text(title).multilineTextAlignment(.center)
        }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private struct SearchRequest: Equatable {
        let query: String
        let currentOnly: Bool
        let revision: Int
    }
}

#if os(macOS)
/// Observe user intent over the feed, including scrollbar drags, without consuming events.
struct SearchScrollInterruption: NSViewRepresentable {
    let onScroll: () -> Void
    func makeNSView(context: Context) -> Observer { Observer(onScroll: onScroll) }
    func updateNSView(_ nsView: Observer, context: Context) { nsView.onScroll = onScroll }
    static func dismantleNSView(_ nsView: Observer, coordinator: ()) { nsView.removeMonitor() }
    final class Observer: NSView {
        var onScroll: () -> Void
        private var monitor: Any?
        init(onScroll: @escaping () -> Void) {
            self.onScroll = onScroll
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .leftMouseDown]) { [weak self] event in
                if let self, let window = self.window, event.window === window,
                   self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { self.onScroll() }
                return event
            }
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        func removeMonitor() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor = nil }
    }
}
#endif
