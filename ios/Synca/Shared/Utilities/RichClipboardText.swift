import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Converts only structured clipboard lists. The editor still receives a plain String.
/// HTML is tokenized locally: no web view, HTML importer, URL resolution or resource loading.
enum RichClipboardText {
    private static let maximumBytes = 1_048_576

    static func string(plainText: String?, html: Data?, rtf: Data?) -> String? {
        if let html, html.count <= maximumBytes,
           let source = String(data: html, encoding: .utf8),
           let converted = htmlList(source) { return converted }
        if let rtf, rtf.count <= maximumBytes, let converted = rtfList(rtf) { return converted }
        return plainText
    }

    private struct List {
        let ordered: Bool
        var next: Int
    }
    private struct Item {
        let depth: Int
        let marker: String
        var emitted = false
    }

    private static func htmlList(_ source: String) -> String? {
        // Mixed code blocks must retain the supplied plain-text whitespace.
        guard source.range(of: #"(?i)<pre\b"#, options: .regularExpression) == nil else { return nil }
        let source = source.replacingOccurrences(
            of: #"(?is)<!--.*?-->|<(script|style|head|iframe|object|template)\b[^>]*>.*?</\1\s*>"#,
            with: "", options: .regularExpression)
        guard let tokenizer = try? NSRegularExpression(pattern: #"<(?:(?:"[^"]*")|(?:'[^']*')|[^'">])*>|[^<]+"#) else { return nil }
        let ns = source as NSString
        let tokens = tokenizer.matches(in: source, range: NSRange(location: 0, length: ns.length))
        var lists: [List] = []
        var items: [Item] = []
        var lines: [String] = []
        var line = ""
        var sawList = false
        func flush(includeEmpty: Bool = false) {
            let content = line.trimmingCharacters(in: .whitespacesAndNewlines)
            line = ""
            guard !content.isEmpty || includeEmpty else { return }
            if let item = items.last {
                let indent = String(repeating: "    ", count: item.depth - 1)
                lines.append(indent + (item.emitted ? "    " : item.marker + " ") + content)
                items[items.count - 1].emitted = true
            } else { lines.append(content) }
        }
        for token in tokens {
            let value = ns.substring(with: token.range)
            guard value.hasPrefix("<") else {
                line += decodeEntities(value).replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                continue
            }
            let closing = value.hasPrefix("</")
            let tag = value.dropFirst(closing ? 2 : 1).prefix { $0.isLetter || $0.isNumber }.lowercased()
            switch tag {
            case "ul", "ol":
                flush()
                if closing {
                    guard let current = lists.last, current.ordered == (tag == "ol"),
                          items.last?.depth != lists.count else { return nil }
                    lists.removeLast()
                } else {
                    guard lists.count < 32 else { return nil }
                    lists.append(List(ordered: tag == "ol", next: integerAttribute("start", in: value) ?? 1))
                    sawList = true
                }
            case "li":
                if closing {
                    guard items.last?.depth == lists.count else { return nil }
                    flush(includeEmpty: items.last?.emitted == false)
                    items.removeLast()
                } else {
                    guard !lists.isEmpty, items.last?.depth != lists.count else { return nil }
                    flush()
                    let index = lists.count - 1
                    let number = integerAttribute("value", in: value) ?? lists[index].next
                    let marker = lists[index].ordered ? "\(number)." : "-"
                    lists[index].next = number < Int.max ? number + 1 : number
                    items.append(Item(depth: lists.count, marker: marker))
                }
            case "br", "p", "div", "section", "article", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "tr":
                flush()
            default: break
            }
        }
        flush()
        guard sawList, lists.isEmpty, items.isEmpty, !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private static func integerAttribute(_ name: String, in tag: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: "(?i)\\s\(name)\\s*=\\s*[\"']?(-?[0-9]+)"),
              let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
              let range = Range(match.range(at: 1), in: tag) else { return nil }
        return Int(tag[range])
    }

    private static func decodeEntities(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z]+);"#) else { return text }
        let names = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ",
                     "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "copy": "©", "reg": "®"]
        var result = text
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let keyRange = Range(match.range(at: 1), in: text), let range = Range(match.range, in: result) else { continue }
            let key = String(text[keyRange])
            var replacement = names[key]
            if key.hasPrefix("#") {
                let hex = key.hasPrefix("#x")
                if let code = UInt32(key.dropFirst(hex ? 2 : 1), radix: hex ? 16 : 10),
                   let scalar = UnicodeScalar(code), code != 0 { replacement = String(scalar) }
            }
            if let replacement { result.replaceSubrange(range, with: replacement) }
        }
        return result
    }

    private static func rtfList(_ data: Data) -> String? {
        guard let rich = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil),
              rich.length > 0 else { return nil }
        let source = rich.string as NSString
        var offset = 0
        var counters: [ObjectIdentifier: Int] = [:]
        var lines: [String] = []
        var sawList = false
        while offset < source.length {
            let range = source.paragraphRange(for: NSRange(location: offset, length: 0))
            var content = source.substring(with: range).trimmingCharacters(in: .newlines)
            let style = rich.attribute(.paragraphStyle, at: offset, effectiveRange: nil) as? NSParagraphStyle
            if let list = style?.textLists.last, let depth = style?.textLists.count {
                sawList = true
                let identity = ObjectIdentifier(list)
                let number = counters[identity] ?? list.startingItemNumber
                counters[identity] = number < Int.max ? number + 1 : number
                let nativeMarker = list.marker(forItemNumber: number)
                // Cocoa RTF commonly stores a literal marker between tabs as well as metadata.
                let trimmed = content.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(nativeMarker), trimmed.dropFirst(nativeMarker.count).first?.isWhitespace == true {
                    content = String(trimmed.dropFirst(nativeMarker.count)).trimmingCharacters(in: .whitespaces)
                } else { content = trimmed }
                let format = list.markerFormat.rawValue.lowercased()
                let unordered = ["disc", "circle", "square", "diamond", "hyphen", "check", "box"].contains { format.contains($0) }
                lines.append(String(repeating: "    ", count: min(31, max(0, depth - 1))) + (unordered ? "- " : "\(number). ") + content)
            } else { lines.append(content) }
            offset = NSMaxRange(range)
        }
        return sawList ? lines.joined(separator: "\n") : nil
    }
}
