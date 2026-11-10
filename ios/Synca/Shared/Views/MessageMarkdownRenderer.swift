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

/// Display-only formatting: stored text and editor/copy actions retain the original source.
@MainActor
enum MessageMarkdownRenderer {
    private static let listPattern = try! NSRegularExpression(pattern: #"^([ \t]*)([-+*]|[0-9]{1,9}[.)])[ \t]+(.*)$"#)
    private static let quotePattern = try! NSRegularExpression(pattern: #"^[ \t]*(>+)[ \t]?(.*)$"#)
    // Keep detection aligned with Web: ordinary records bypass Markdown escape/entity decoding.
    private static let basicPattern = try! NSRegularExpression(pattern: #"(^|\n) {0,3}(?:[-+*] |\d+[.)] |> ?)|\*\*[^\n]+\*\*|__[^\n]+__|\*(?!\s)[^*\n]*\S\*|(?:^|[^\p{L}\p{N}_])_(?!\s)[^_\n]*\S_(?![\p{L}\p{N}_])|`[^`\n]+`|(?<!!)\[[^\]\n]+\]\([^\n]+\)"#)
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static let codeKey = NSAttributedString.Key("SyncaMarkdownCode")

    static func render(_ source: String, baseColor: MarkdownColor) -> NSAttributedString {
        let font = MarkdownFont.preferredFont(forTextStyle: .body)
        let result = NSMutableAttributedString(string: "")
        let hasMarkdown = basicPattern.firstMatch(in: source, range: NSRange(location: 0, length: source.utf16.count)) != nil
        let lines = source.components(separatedBy: "\n")
        var fence: (character: Character, count: Int)?
        var orderedCounters: [Int: Int] = [:]
        for (index, line) in lines.enumerated() {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            var body = line
            var prefix = ""
            let paragraph = NSMutableParagraphStyle()
            // Scale indents with body text; leave ordinary paragraphs at their existing spacing.
            let indent = font.pointSize * 1.35
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let fenceCharacter = trimmed.first
            let fenceCount = trimmed.prefix { $0 == fenceCharacter }.count
            let isFence = (fenceCharacter == "`" || fenceCharacter == "~") && fenceCount >= 3
            let literal = !hasMarkdown || fence != nil || isFence
            if let active = fence {
                if fenceCharacter == active.character && fenceCount >= active.count && trimmed.dropFirst(fenceCount).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
            } else if isFence, let fenceCharacter {
                fence = (fenceCharacter, fenceCount)
            }
            if !literal, let match = listPattern.firstMatch(in: line, range: range) {
                let whitespace = nsLine.substring(with: match.range(at: 1)).replacingOccurrences(of: "\t", with: "    ")
                let marker = nsLine.substring(with: match.range(at: 2))
                body = nsLine.substring(with: match.range(at: 3))
                let depth = whitespace.count
                orderedCounters = orderedCounters.filter { $0.key <= depth }
                if marker.first?.isNumber == true {
                    let number = orderedCounters[depth].map { $0 + 1 } ?? Int(marker.dropLast()) ?? 1
                    orderedCounters[depth] = number
                    prefix = "\(number).\t"
                } else {
                    orderedCounters[depth] = nil
                    prefix = "•\t"
                }
                paragraph.firstLineHeadIndent = CGFloat(min(whitespace.count / 2, 8)) * indent
                let markerWidth = (prefix.replacingOccurrences(of: "\t", with: "") as NSString).size(withAttributes: [.font: font]).width
                paragraph.headIndent = paragraph.firstLineHeadIndent + max(indent, markerWidth + font.pointSize * 0.4)
            } else if !literal, let match = quotePattern.firstMatch(in: line, range: range) {
                body = nsLine.substring(with: match.range(at: 2))
                prefix = "│\t"
                paragraph.firstLineHeadIndent = CGFloat(min(match.range(at: 1).length - 1, 8)) * indent
                paragraph.headIndent = paragraph.firstLineHeadIndent + indent
            }
            if prefix.isEmpty && !trimmed.isEmpty { orderedCounters.removeAll() }
            if !prefix.isEmpty {
                paragraph.tabStops = [NSTextTab(textAlignment: .left, location: paragraph.headIndent)]
                paragraph.defaultTabInterval = indent
            }
            let lineResult = NSMutableAttributedString(string: prefix, attributes: [.font: font, .foregroundColor: baseColor])
            if !hasMarkdown {
                lineResult.append(NSAttributedString(string: body, attributes: [.font: font, .foregroundColor: baseColor]))
            } else if literal || body.contains("![") {
                lineResult.append(NSAttributedString(string: body, attributes: [.font: font, .foregroundColor: baseColor, codeKey: true]))
            } else {
                lineResult.append(inline(body, font: font, color: baseColor))
            }
            if index < lines.count - 1 { lineResult.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: baseColor])) }
            lineResult.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: lineResult.length))
            result.append(lineResult)
        }
        let fullRange = NSRange(location: 0, length: result.length)
        detector?.enumerateMatches(in: result.string, range: fullRange) { match, _, _ in
            guard let match, let url = match.url, isSafeLink(url),
                  result.attribute(.link, at: match.range.location, effectiveRange: nil) == nil,
                  result.attribute(codeKey, at: match.range.location, effectiveRange: nil) == nil else { return }
            result.addAttribute(.link, value: url, range: match.range)
        }
        result.enumerateAttribute(.link, in: fullRange) { value, range, _ in
            guard value != nil else { return }
            #if os(iOS)
            let linkColor = UIColor.link
            #else
            let linkColor = NSColor.linkColor
            #endif
            result.addAttributes([.foregroundColor: linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue], range: range)
        }
        return result
    }

    private static func isSafeLink(_ url: URL) -> Bool {
        ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "")
    }

    private static func inline(_ source: String, font: MarkdownFont, color: MarkdownColor) -> NSAttributedString {
        guard let parsed = try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return NSAttributedString(string: source, attributes: [.font: font, .foregroundColor: color])
        }
        let output = NSMutableAttributedString(string: "")
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            var runFont = font
            if intent.contains(.code) {
                runFont = MarkdownFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular)
            }
            #if os(iOS)
            var traits = runFont.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.traitBold) }
            if intent.contains(.emphasized) { traits.insert(.traitItalic) }
            if let descriptor = runFont.fontDescriptor.withSymbolicTraits(traits) { runFont = UIFont(descriptor: descriptor, size: font.pointSize) }
            #else
            var traits = runFont.fontDescriptor.symbolicTraits
            if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
            if intent.contains(.emphasized) { traits.insert(.italic) }
            runFont = NSFont(descriptor: runFont.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? runFont
            #endif
            var attributes: [NSAttributedString.Key: Any] = [.font: runFont, .foregroundColor: color]
            if let link = run.link, isSafeLink(link) { attributes[.link] = link }
            if intent.contains(.code) { attributes[codeKey] = true }
            output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: attributes))
        }
        return output
    }

    /// Count actual rendered TextKit fragments, including list indentation and inline font traits.
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
