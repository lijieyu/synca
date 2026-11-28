import Foundation
#if os(iOS)
import UIKit
private typealias MarkdownFont = UIFont
typealias MarkdownColor = UIColor
#elseif os(macOS)
import AppKit
private typealias MarkdownFont = NSFont
typealias MarkdownColor = NSColor
#endif

/// Native attributes are derived from the same AST as Web. Source remains untouched.
@MainActor
enum MessageMarkdownRenderer {
    private static let headingScales: [CGFloat] = [1.55, 1.4, 1.25, 1.15, 1.075, 1]
    static func render(_ source: String, baseColor: MarkdownColor) -> NSAttributedString {
        render(document: MarkdownParser.shared.parse(source), baseColor: baseColor)
    }
    static func render(document: MarkdownDocument, baseColor: MarkdownColor) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        for (index, node) in document.children.enumerated() {
            if index > 0 { output.append(NSAttributedString(string: "\n")) }
            output.append(block(node, color: baseColor))
        }
        return output
    }
    static func inline(_ nodes: [MarkdownNode], baseColor: MarkdownColor, heading: Int? = nil) -> NSAttributedString {
        let body = MarkdownFont.preferredFont(forTextStyle: .body)
        let font = heading.map { MarkdownFont.systemFont(ofSize: body.pointSize * headingScales[max(0, min(5, $0 - 1))], weight: .semibold) } ?? body
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: baseColor]
        #if os(iOS)
        if let heading { attributes[.accessibilityTextHeadingLevel] = heading }
        #endif
        return styled(nodes, attributes: attributes)
    }
    private static func styled(_ nodes: [MarkdownNode], attributes: [NSAttributedString.Key: Any]) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        for node in nodes {
            var next = attributes
            let font = (next[.font] as? MarkdownFont) ?? MarkdownFont.preferredFont(forTextStyle: .body)
            switch node.type {
            case "strong", "emphasis":
                var traits = font.fontDescriptor.symbolicTraits
                #if os(iOS)
                traits.insert(node.type == "strong" ? .traitBold : .traitItalic)
                if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { next[.font] = UIFont(descriptor: descriptor, size: font.pointSize) }
                #else
                traits.insert(node.type == "strong" ? .bold : .italic)
                next[.font] = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
                #endif
            case "inlineCode", "code":
                next[.font] = MarkdownFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            case "delete": next[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            case "underline": next[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case "link":
                if let raw = node.url, let url = URL(string: raw), ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                    next[.link] = url
                    next[.underlineStyle] = NSUnderlineStyle.single.rawValue
                    #if os(iOS)
                    next[.foregroundColor] = UIColor.link
                    #else
                    next[.foregroundColor] = NSColor.linkColor
                    #endif
                }
            default: break
            }
            if let children = node.children { output.append(styled(children, attributes: next)) }
            else { output.append(NSAttributedString(string: node.text, attributes: next)) }
        }
        return output
    }
    private static func block(_ node: MarkdownNode, color: MarkdownColor, depth: Int = 0) -> NSAttributedString {
        switch node.type {
        case "list":
            let result = NSMutableAttributedString(string: "")
            for (index, item) in (node.children ?? []).enumerated() {
                if index > 0 { result.append(NSAttributedString(string: "\n")) }
                let prefix = item.checked.map { $0 ? "☑\t" : "☐\t" } ?? (node.ordered == true ? "\((node.start ?? 1) + index).\t" : "•\t")
                let line = NSMutableAttributedString(string: prefix, attributes: [.font: MarkdownFont.preferredFont(forTextStyle: .body), .foregroundColor: color])
                for (childIndex, child) in (item.children ?? []).enumerated() {
                    if childIndex > 0 { line.append(NSAttributedString(string: "\n")) }
                    line.append(block(child, color: color, depth: depth + 1))
                }
                let paragraph = NSMutableParagraphStyle()
                let indent = MarkdownFont.preferredFont(forTextStyle: .body).pointSize * 1.35
                paragraph.firstLineHeadIndent = CGFloat(depth) * indent
                paragraph.headIndent = CGFloat(depth + 1) * indent
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                // Preserve deeper list styles already set by recursive rendering.
                var unstyled: [NSRange] = []
                line.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: line.length)) { value, range, _ in
                    if value == nil { unstyled.append(range) }
                }
                for range in unstyled { line.addAttribute(.paragraphStyle, value: paragraph, range: range) }
                result.append(line)
            }
            return result
        case "blockquote", "listItem", "table", "tableRow":
            let result = NSMutableAttributedString(string: node.type == "blockquote" ? "│\t" : "")
            for (index, child) in (node.children ?? []).enumerated() {
                if index > 0 { result.append(NSAttributedString(string: node.type == "tableRow" ? "\t" : "\n")) }
                result.append(block(child, color: color, depth: depth))
            }
            return result
        case "thematicBreak": return inline([MarkdownNode(type: "text", value: "────────")], baseColor: color)
        case "code": return inline([node], baseColor: color)
        default: return inline(node.children ?? [node], baseColor: color, heading: node.type == "heading" ? node.depth : nil)
        }
    }

    /// Count actual rendered TextKit fragments, including list indentation and inline font traits.
    /// Match the rendered TextKit layout so a search hit can be anchored without changing row geometry.
    static func matchOffset(_ attributed: NSAttributedString, text: String, width: CGFloat) -> CGFloat {
        let range = (attributed.string as NSString).range(of: text, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        guard range.location != NSNotFound, width > 0 else { return 0 }
        let storage = NSTextStorage(attributedString: attributed)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let glyph = manager.glyphIndexForCharacter(at: range.location)
        return max(0, manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).minY - 8)
    }

    static func overflows(_ text: NSAttributedString, width: CGFloat, maximumLines: Int) -> Bool {
        guard width > 0, text.length > 0 else { return false }
        let storage = NSTextStorage(attributedString: text)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        var count = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, _, _, _, stop in
            count += 1
            if count > maximumLines { stop.pointee = true }
        }
        return count > maximumLines
    }
}
