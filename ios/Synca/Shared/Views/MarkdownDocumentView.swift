import SwiftUI

/// One native document tree for both saved records and scratchpad previews.
/// Image URLs can only come from the current host's authenticated asset resolver.
struct MarkdownDocumentView: View {
    let source: String
    var secondary = false
    var taskBusy = false
    var tasksEnabled = true
    var onToggleTask: ((Int) -> Void)?
    var imageURL: ((String) -> URL?)?
    var searchText: String?
    var onSearchOffset: ((CGFloat) -> Void)?
    #if os(macOS)
    var contextMenuActions: [MacMessageMenuAction] = []
    #endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Namespace private var documentSpace
    @State private var loadedSource: String?
    @State private var loadedDocument: MarkdownDocument?
    @State private var listPages: [Int: Int] = [:]
    private static let pageSize = 128
    private var color: MarkdownColor {
        #if os(iOS)
        secondary ? .secondaryLabel : .label
        #else
        secondary ? .secondaryLabelColor : .labelColor
        #endif
    }
    var body: some View {
        let large = source.utf16.count > 32_000
        let document = large ? (loadedSource == source ? loadedDocument : MarkdownParser.shared.cachedDocument(source)) : MarkdownParser.shared.parse(source)
        Group {
            if let document { blocks(document.children) }
            else { ProgressView("markdown.loading").frame(maxWidth: .infinity, minHeight: 44) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .coordinateSpace(name: documentSpace)
        .onPreferenceChange(MarkdownSearchOffset.self) { value in
            if let value { onSearchOffset?(value) }
        }
        .task(id: source) {
            guard large else { return }
            let document = await MarkdownParser.shared.parseAsync(source)
            guard !Task.isCancelled else { return }
            loadedSource = source; loadedDocument = document
        }
        .onChange(of: searchText) { _ in listPages = [:] }
    }
    private func blocks(_ nodes: [MarkdownNode]) -> AnyView {
        // Coalesce very long runs of ordinary text into TextKit storage. This keeps
        // full height/search geometry exact without mounting thousands of text views.
        if nodes.count > 128 {
            let groups = textGroups(nodes)
            return AnyView(VStack(alignment: .leading, spacing: 10) {
                ForEach(groups.indices, id: \.self) { index in
                    let group = groups[index]
                    if group.count > 1 {
                        selectable(MessageMarkdownRenderer.render(document: MarkdownDocument(version: 1, type: "root", plain: false, children: group), baseColor: color))
                    } else if let node = group.first { block(node) }
                }
            })
        }
        return AnyView(VStack(alignment: .leading, spacing: 10) {
            ForEach(nodes.indices, id: \.self) { block(nodes[$0]) }
        })
    }
    private func textGroups(_ nodes: [MarkdownNode]) -> [[MarkdownNode]] {
        var groups: [[MarkdownNode]] = [], current: [MarkdownNode] = []
        for node in nodes {
            if ["paragraph", "heading"].contains(node.type), !node.descendants.contains(where: { $0.type == "image" }) {
                current.append(node)
            } else {
                if !current.isEmpty { groups.append(current); current = [] }
                groups.append([node])
            }
        }
        if !current.isEmpty { groups.append(current) }
        return groups
    }
    private func block(_ node: MarkdownNode) -> AnyView {
        switch node.type {
        case "heading":
            return AnyView(inlineContent(node.children ?? [], heading: node.depth).accessibilityAddTraits(.isHeader).padding(.top, 3))
        case "paragraph", "tableCell": return inlineContent(node.children ?? [])
        case "blockquote":
            return AnyView(HStack(alignment: .top, spacing: 10) {
                blocks(node.children ?? []).padding(.leading, 12)
                    .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 1).fill(.secondary.opacity(0.4)).frame(width: 3) }
            })
        case "list":
            // Long noninteractive outlines use one selectable layout manager rather
            // than one native view per bullet. Complex/task items retain controls.
            if (node.children?.count ?? 0) > 128,
               node.descendants.allSatisfy({ ["list", "listItem", "paragraph", "text", "strong", "emphasis", "delete", "underline", "inlineCode", "link", "break", "html"].contains($0.type) && $0.checked == nil }) {
                return selectable(MessageMarkdownRenderer.render(document: MarkdownDocument(version: 1, type: "root", plain: false, children: [node]), baseColor: color))
            }
            let items = node.children ?? []
            let key = node.position?.start.offset ?? 0
            let searchIndex = searchText.flatMap { term in items.firstIndex { $0.text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil } }
            let requestedPage = listPages[key] ?? (searchIndex.map { $0 / Self.pageSize } ?? 0)
            let page = max(0, min(requestedPage, max(0, items.count - 1) / Self.pageSize))
            let start = min(page * Self.pageSize, max(0, items.count - 1))
            let end = min(start + Self.pageSize, items.count)
            return AnyView(VStack(alignment: .leading, spacing: 6) {
                if items.count > Self.pageSize { listNavigation(key: key, page: page, start: start, end: end, total: items.count) }
                ForEach(Array(items[start..<end].enumerated()), id: \.offset) { localIndex, item in
                    let index = start + localIndex
                    HStack(alignment: .top, spacing: 5) {
                        if let checked = item.checked, let offset = item.taskOffset {
                            Button { onToggleTask?(offset) } label: {
                                Image(systemName: checked ? "checkmark.square.fill" : "square")
                                    .font(.body).frame(minWidth: 44, minHeight: 44)
                            }.buttonStyle(.plain)
                                .disabled(taskBusy || !tasksEnabled || onToggleTask == nil)
                                .accessibilityLabel(Text(item.children?.first?.text ?? item.text))
                                .accessibilityValue(Text(taskBusy ? "markdown.task_saving" : checked ? "markdown.task_checked" : "markdown.task_unchecked"))
                                .accessibilityHint(Text(checked ? "markdown.task_uncheck" : "markdown.task_check"))
                                .accessibilityIdentifier("markdown-task-\(offset)")

                        } else {
                            Text(node.ordered == true ? "\((node.start ?? 1) + index)." : "•")
                                .monospacedDigit().frame(minWidth: 20, alignment: .trailing).accessibilityHidden(true)
                        }
                        blocks(item.children ?? []).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, item.checked == nil ? 0 : 10)
                    }
                }
            })
        case "code":
            return AnyView(ScrollView(.horizontal) {
                selectable(MessageMarkdownRenderer.inline([node], baseColor: color), horizontal: true)
                    .padding(12)
            }.background(.quaternary, in: RoundedRectangle(cornerRadius: 8)))
        case "thematicBreak": return AnyView(Divider().padding(.vertical, 4))
        case "table": return table(node)
        case "image": return image(node)
        default:
            if let children = node.children { return blocks(children) }
            return selectable(MessageMarkdownRenderer.inline([node], baseColor: color))
        }
    }
    private func listNavigation(key: Int, page: Int, start: Int, end: Int, total: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(format: String(syncaLocalized: "markdown.item_range"), start + 1, end, total))
                .font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("markdown-item-range-\(key)")
            HStack {
                Button("markdown.previous_items") { listPages[key] = max(0, page - 1) }.disabled(start == 0).accessibilityIdentifier("markdown-previous-items-\(key)")
                Spacer()
                Button("markdown.next_items") { listPages[key] = page + 1 }.disabled(end == total).accessibilityIdentifier("markdown-next-items-\(key)")
            }.buttonStyle(.borderless).frame(minHeight: 44)
        }
    }
    private func inlineContent(_ originalNodes: [MarkdownNode], heading: Int? = nil, alignment: NSTextAlignment = .left) -> AnyView {
        let nodes = expandInlineImages(originalNodes)
        // Keep surrounding styled text selectable; only actual parsed images split a paragraph.
        guard nodes.contains(where: { $0.descendants.contains { $0.type == "image" } }) else {
            return selectable(inlineText(nodes, heading: heading, alignment: alignment))
        }
        var groups: [[MarkdownNode]] = []
        var current: [MarkdownNode] = []
        for node in nodes {
            if node.type == "image" {
                if !current.isEmpty { groups.append(current); current = [] }
                groups.append([node])
            } else { current.append(node) }
        }
        if !current.isEmpty { groups.append(current) }
        return AnyView(VStack(alignment: .leading, spacing: 8) {
            ForEach(groups.indices, id: \.self) { index in
                if groups[index].count == 1, groups[index][0].type == "image" { image(groups[index][0]) }
                else { selectable(inlineText(groups[index], heading: heading, alignment: alignment)) }
            }
        })
    }
    private func inlineText(_ nodes: [MarkdownNode], heading: Int?, alignment: NSTextAlignment) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: MessageMarkdownRenderer.inline(nodes, baseColor: color, heading: heading))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        result.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: result.length))
        return result
    }
    private func expandInlineImages(_ nodes: [MarkdownNode]) -> [MarkdownNode] {
        nodes.flatMap { node -> [MarkdownNode] in
            guard let children = node.children, children.contains(where: { $0.descendants.contains { $0.type == "image" } }) else { return [node] }
            return expandInlineImages(children).map { child in
                if child.type == "image" { return child }
                var wrapper = node
                wrapper.children = [child]
                return wrapper
            }
        }
    }
    private func selectable(_ text: NSAttributedString, horizontal: Bool = false) -> AnyView {
        let match = searchText.flatMap { term -> String? in
            guard !term.isEmpty, text.string.range(of: term, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]) != nil else { return nil }
            return term
        }
        let naturalWidth = ceil(text.size().width) + 2
        return AnyView(Group {
            #if os(iOS)
            LinkTextView(attributedText: text)
            #else
            MacSelectableText(attributedText: text, color: secondary ? .secondary : .primary, font: .body, contextMenuActions: contextMenuActions)
            #endif
        }
        .frame(width: horizontal ? max(1, naturalWidth) : nil, alignment: .leading)
        .frame(maxWidth: horizontal ? nil : .infinity, alignment: .leading)
        .background(GeometryReader { geometry in
            if let match {
                Color.clear.preference(key: MarkdownSearchOffset.self,
                    value: geometry.frame(in: .named(documentSpace)).minY + MessageMarkdownRenderer.matchOffset(text, text: match, width: geometry.size.width))
            }
        }))
    }
    private func table(_ node: MarkdownNode) -> AnyView {
        let rows = node.children ?? []
        let columns = rows.map { ($0.children ?? []).count }.max() ?? 0
        let widths: [CGFloat] = (0..<columns).map { column in
            let natural = rows.map { row -> CGFloat in
                guard let cells = row.children, column < cells.count else { return 0 }
                return MessageMarkdownRenderer.inline(cells[column].children ?? [], baseColor: color).size().width + 24
            }.max() ?? 100
            return min(340, max(100, natural))
        }
        return AnyView(ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(alignment: .top, spacing: 0) {
                        ForEach(0..<columns, id: \.self) { column in
                            let cells = rows[row].children ?? []
                            let nodes = column < cells.count ? cells[column].children ?? [] : []
                            let alignment = (node.align?.indices.contains(column) == true ? node.align?[column] : nil) ?? "left"
                            inlineContent(row == 0 ? [MarkdownNode(type: "strong", children: nodes)] : nodes,
                                alignment: alignment == "right" ? .right : alignment == "center" ? .center : .left)
                                .padding(10).frame(width: widths[column], alignment: alignment == "right" ? .trailing : alignment == "center" ? .center : .leading)
                        }
                    }.background(row == 0 ? Color.secondary.opacity(0.12) : row.isMultiple(of: 2) ? Color.secondary.opacity(0.04) : Color.clear)
                    Divider()
                }
            }
            .frame(width: widths.reduce(0, +), alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.25)))
        })
    }
    private func image(_ node: MarkdownNode) -> AnyView {
        if let id = node.ownedImageID, let url = imageURL?(id) {
            return AnyView(CachedAsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit().frame(maxHeight: 480) }
                else { Label("scratch.image", systemImage: "photo").foregroundStyle(.secondary).frame(minHeight: 64) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isImage)
            .accessibilityLabel(Text(node.alt?.isEmpty == false ? node.alt! : String(syncaLocalized: "scratch.image"))))
        }
        return selectable(MessageMarkdownRenderer.inline([MarkdownNode(type: "text", value: node.source ?? node.alt ?? String(syncaLocalized: "scratch.image"))], baseColor: color))
    }
}

private struct MarkdownSearchOffset: PreferenceKey {
    static var defaultValue: CGFloat? { nil }
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        if let next = nextValue() { value = min(value ?? next, next) }
    }
}

@MainActor func markdownTaskFeedback(success: Bool, message: String? = nil) {
    let announcement = message ?? String(syncaLocalized: success ? "markdown.task_updated" : "message_edit.failed")
    #if os(iOS)
    UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
    UIAccessibility.post(notification: .announcement, argument: announcement)
    #elseif os(macOS)
    NSAccessibility.post(element: NSApp.mainWindow as Any, notification: .announcementRequested,
        userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    #endif
}

/// Shared account-scoped storage coalesces owned-image metadata reads across feed rows.
struct AuthenticatedMarkdownAssets<Content: View>: View {
    @ObservedObject private var store: ScratchpadStore
    let source: String
    let content: ([String: URL]) -> Content
    init(account: String, source: String, @ViewBuilder content: @escaping ([String: URL]) -> Content) {
        store = ScratchpadStore.shared(account: account)
        self.source = source
        self.content = content
    }
    var body: some View {
        let urls = store.images.reduce(into: [String: URL]()) { result, image in
            if let url = store.previewImageURL(id: image.id) { result[image.id.lowercased()] = url }
        }
        content(urls).task(id: source) {
            let document = await MarkdownParser.shared.parseAsync(source)
            guard !Task.isCancelled, document.children.contains(where: { $0.descendants.contains { $0.ownedImageID != nil } }) else { return }
            await store.loadPreviewImages()
        }
    }
}
