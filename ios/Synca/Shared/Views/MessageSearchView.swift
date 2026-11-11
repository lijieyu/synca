import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Search owns its index and scope so dismissing it cannot mutate the feed.
struct MessageSearchView: View {
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    let currentCategoryID: String?
    @Binding var query: String
    let onSelect: (MessageSearchResult) -> Bool
    @State private var hasDraft = false
    @State private var clearRevision = 0
    @State private var currentOnly = false
    @State private var results: [MessageSearchResult] = []
    @State private var displayedQuery = ""
    @State private var unavailable = false
    @State private var revision = 0
    @State private var index = MessageSearchIndex()
    @ScaledMetric(relativeTo: .body) private var queryFieldHeight = 22.0

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            MacSheetHeader(title: "search.title")
            Divider()
            content
        }
        .frame(width: 640, height: 560)
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
                SearchQueryField(text: $query, placeholder: String(syncaLocalized: "search.placeholder"),
                                 clearRevision: clearRevision, onDraftChange: { hasDraft = $0 })
                    .frame(maxWidth: .infinity)
                    .frame(height: queryFieldHeight)
                if !query.isEmpty || hasDraft {
                    Button { query = ""; hasDraft = false; clearRevision += 1 } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
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
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayedQuery.isEmpty {
                emptyState("search.prompt", symbol: "magnifyingglass")
            } else if results.isEmpty {
                emptyState("search.empty", symbol: "doc.text.magnifyingglass")
            } else {
                Text(String(format: String(syncaLocalized: "search.count"), results.count))
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results) { result in
                            Button {
                                unavailable = !onSelect(result)
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
                                    highlightedText(result.excerpt, ranges: result.excerptRanges).font(.body).foregroundStyle(.primary).lineLimit(3)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if let filename = result.message.fileName, !filename.isEmpty, filename != result.excerpt {
                                        Label { highlightedText(filename, ranges: result.filenameRanges, font: .subheadline) } icon: { Image(systemName: "doc") }.font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    }
                                    ViewThatFits(in: .horizontal) {
                                        HStack(spacing: 8) {
                                            resultCategory(result.message).fixedSize()
                                            Spacer(minLength: 8)
                                            Text(result.message.displayDate).monospacedDigit().fixedSize()
                                        }
                                        VStack(alignment: .leading, spacing: 5) {
                                            resultCategory(result.message)
                                            Text(result.message.displayDate).monospacedDigit()
                                                .frame(maxWidth: .infinity, alignment: .trailing)
                                        }
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical, 14).padding(.horizontal, 6).contentShape(Rectangle())
                            }.buttonStyle(SearchResultButtonStyle()).accessibilityHint(Text("search.open_hint"))
                                .accessibilityIdentifier("search-result-\(result.id)")
                            if result.id != results.last?.id { Divider() }
                        }
                    }
                    .padding(.trailing, 12)
                }
            }
        }
        .padding(20)
        .background(Color.syncaPageBackground)
        .onReceive(syncManager.$messages) { _ in revision += 1 }
        .task(id: SearchRequest(query: query, currentOnly: currentOnly, revision: revision)) {
            unavailable = false
            guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                results = []
                displayedQuery = ""
                return
            }
            let requestedQuery = query
            let snapshot = syncManager.messages
            let matches = await index.search(snapshot, query: query, categoryID: currentOnly ? currentCategoryID : nil, excerptTailContext: excerptTailContext)
            guard !Task.isCancelled else { return }
            results = matches
            displayedQuery = requestedQuery
        }
    }

    private var excerptTailContext: Int {
        #if os(macOS)
        96
        #else
        48
        #endif
    }

    private func resultCategory(_ message: SyncaMessage) -> some View {
        HStack(spacing: 6) {
            Circle().fill(categoryColor(message)).frame(width: 8, height: 8).accessibilityHidden(true)
            Text(categoryName(message)).lineLimit(1)
            if message.isCleared {
                Image(systemName: "checkmark.circle.fill").accessibilityLabel(Text("search.completed"))
            }
        }
    }

    private var currentCategoryName: String {
        guard let category = syncManager.categories.first(where: { $0.id == currentCategoryID }) else {
            return String(syncaLocalized: "search.current")
        }
        return category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name
    }

    private func categoryColor(_ message: SyncaMessage) -> Color {
        let category = syncManager.categories.first { $0.id == message.categoryId }
        return categoryDisplayColor(category?.color ?? message.categoryColor ?? .slate,
                                    hex: category?.colorHex ?? message.categoryColorHex)
    }

    private func categoryName(_ message: SyncaMessage) -> String {
        if let category = syncManager.categories.first(where: { $0.id == message.categoryId }) {
            return category.isDefault ? String(syncaLocalized: "message_category.default_badge") : category.name
        }
        return message.categoryIsDefault == true ? String(syncaLocalized: "message_category.default_badge")
            : message.categoryName ?? String(syncaLocalized: "message_category.default_badge")
    }

    private func highlightedText(_ text: String, ranges: [Range<Int>], font: Font = .body) -> some View {
        var attributed = AttributedString(text)
        for range in ranges {
            guard let sourceRange = Range(NSRange(location: range.lowerBound, length: range.count), in: text),
                  let start = AttributedString.Index(sourceRange.lowerBound, within: attributed),
                  let end = AttributedString.Index(sourceRange.upperBound, within: attributed) else { continue }
            attributed[start..<end].backgroundColor = markerColor
        }
        return Group {
            if #available(iOS 18.0, macOS 15.0, *) {
                markedText(text, ranges: ranges).textRenderer(SearchMarkerRenderer(color: markerColor))
            } else {
                Text(attributed)
            }
        }
    }

    private var markerColor: Color {
        colorScheme == .dark ? Color(red: 36/255, green: 87/255, blue: 136/255)
            : Color(red: 197/255, green: 227/255, blue: 1)
    }

    @available(iOS 18.0, macOS 15.0, *)
    private func markedText(_ text: String, ranges: [Range<Int>]) -> Text {
        var output = Text("")
        var cursor = text.startIndex
        for range in ranges.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            guard let span = Range(NSRange(location: range.lowerBound, length: range.count), in: text),
                  span.lowerBound >= cursor else { continue }
            output = output + Text(String(text[cursor..<span.lowerBound]))
                + Text(String(text[span])).customAttribute(SearchMarkerAttribute())
            cursor = span.upperBound
        }
        return output + Text(String(text[cursor...]))
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

private struct SearchResultButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SearchResultButtonBody(configuration: configuration)
    }
}

private struct SearchResultButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovered = false
    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : isHovered ? 0.06 : 0))
                    .padding(.vertical, 6)
            }
            #if os(macOS)
            .onContinuousHover { phase in
                switch phase {
                case .active: isHovered = true
                case .ended: isHovered = false
                }
            }
            .onDisappear { isHovered = false }
            #endif
    }
}

@available(iOS 18.0, macOS 15.0, *)
private struct SearchMarkerAttribute: TextAttribute {}

@available(iOS 18.0, macOS 15.0, *)
private struct SearchMarkerRenderer: TextRenderer {
    let color: Color
    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            for run in line {
                if run[SearchMarkerAttribute.self] != nil {
                    context.fill(Path(roundedRect: run.typographicBounds.rect, cornerRadius: 2), with: .color(color))
                }
                context.draw(run)
            }
        }
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

// Own the initial selection along with focus: SwiftUI's TextField can reset a
// notification-based selectAll to a trailing caret during sheet presentation.
#if os(iOS)
struct SearchQueryField: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var clearRevision = 0
    var onDraftChange: (Bool) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Field {
        let field = Field()
        field.onCompositionEnded = { [weak field, weak coordinator = context.coordinator] in
            guard let field else { return }; coordinator?.changed(field)
        }
        field.borderStyle = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.textColor = .label
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.returnKeyType = .search
        field.accessibilityIdentifier = "search-query"
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }
    func updateUIView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.placeholder = placeholder
        field.accessibilityLabel = placeholder
        if context.coordinator.clearRevision != clearRevision || context.coordinator.lastCommitted != text || (field.markedTextRange == nil && field.text != text) {
            context.coordinator.clearRevision = clearRevision
            let externalText = text
            context.coordinator.applyingExternal = true
            defer { context.coordinator.applyingExternal = false }
            context.coordinator.lastCommitted = externalText
            // A differing binding is an external clear, not the editing event.
            // Cancel marked text too so an IME cannot restore the old query.
            field.unmarkText()
            field.text = externalText
        }
    }
    final class Field: UITextField {
        var onCompositionEnded: (() -> Void)?
        override func unmarkText() {
            super.unmarkText()
            // Input methods can end composition without an editingChanged event.
            DispatchQueue.main.async { [weak self] in self?.onCompositionEnded?() }
        }
        private var requestedFocus = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, !requestedFocus else { return }
            requestedFocus = true
            DispatchQueue.main.async { [weak self] in
                guard let self, self.window != nil else { return }
                self.becomeFirstResponder()
                self.selectAll(nil)
            }
        }
    }
    final class Coordinator: NSObject {
        var parent: SearchQueryField
        var clearRevision = 0
        var lastCommitted: String
        var applyingExternal = false
        init(_ parent: SearchQueryField) { self.parent = parent; lastCommitted = parent.text }
        @objc func changed(_ field: UITextField) {
            guard !applyingExternal else { return }
            if field.markedTextRange == nil {
                lastCommitted = field.text ?? ""
                parent.text = lastCommitted
            }
            parent.onDraftChange(!(field.text ?? "").isEmpty)
        }
    }
}
#elseif os(macOS)
private struct SearchQueryField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    var clearRevision = 0
    var onDraftChange: (Bool) -> Void = { _ in }
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> Field {
        let field = Field()
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = .labelColor
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("search-query")
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return field
    }
    func updateNSView(_ field: Field, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder)
        if context.coordinator.clearRevision != clearRevision || context.coordinator.lastCommitted != text || ((field.currentEditor() as? NSTextView)?.hasMarkedText() != true && field.stringValue != text) {
            let externalText = text
            context.coordinator.applyingExternal = true
            defer { context.coordinator.applyingExternal = false }
            context.coordinator.clearRevision = clearRevision
            context.coordinator.lastCommitted = externalText
            (field.currentEditor() as? NSTextView)?.unmarkText()
            field.stringValue = externalText
        }
    }
    final class Field: NSTextField {
        var hasUserEdited = false
        private var requestedFocus = false
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil, !requestedFocus else { return }
            requestedFocus = true
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                window.makeFirstResponder(self)
                if !self.hasUserEdited { self.currentEditor()?.selectAll(nil) }
            }
        }
    }
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SearchQueryField
        var applyingExternal = false
        var clearRevision = 0
        var lastCommitted: String
        init(_ parent: SearchQueryField) { self.parent = parent; lastCommitted = parent.text }
        func controlTextDidChange(_ notification: Notification) {
            guard !applyingExternal, let field = notification.object as? NSTextField else { return }
            (field as? Field)?.hasUserEdited = true
            if (field.currentEditor() as? NSTextView)?.hasMarkedText() != true {
                lastCommitted = field.stringValue
                parent.text = lastCommitted
            }
            parent.onDraftChange(!field.stringValue.isEmpty)
        }
    }
}
#endif
