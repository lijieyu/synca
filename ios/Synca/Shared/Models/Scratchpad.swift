import Foundation

struct ScratchDocument: Codable, Sendable {
    var content: String
    var revision: Int
    var updatedAt: String?
}
struct ScratchDraft: Codable, Sendable {
    var content = ""
    var revision = 0
    var dirty = false
    var preserveCurrent = false
    mutating func accept(sent: String, remote: ScratchDocument) {
        revision = remote.revision
        dirty = content != sent
        preserveCurrent = false
    }
    mutating func receive(_ remote: ScratchDocument) {
        guard !dirty else { return }
        content = remote.content
        revision = remote.revision
    }
}
struct ScratchConflict: Decodable, Error { let current: ScratchDocument; let conflictId: String }
struct ScratchCopy: Decodable, Identifiable { let id: String; let content: String; let createdAt: String }
struct ScratchCopies: Decodable { let conflicts: [ScratchCopy] }
struct ScratchImages: Decodable { let images: [SyncaMessage] }

/// Images use stable owned asset IDs; signed or external image URLs never become attachments.
struct ScratchBlock: Identifiable {
    let id: Int
    let text: String
    let imageID: String?
    static func parse(_ text: String) -> [ScratchBlock] {
        let expression = try! NSRegularExpression(pattern: #"!\[[^\]]*\]\(synca-image:([0-9a-fA-F-]{36})\)"#)
        let source = text as NSString
        var result: [ScratchBlock] = []; var position = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            if match.range.location > position {
                result.append(.init(id: result.count, text: source.substring(with: NSRange(location: position, length: match.range.location-position)), imageID: nil))
            }
            result.append(.init(id: result.count, text: "", imageID: source.substring(with: match.range(at: 1)).lowercased()))
            position = match.range.location + match.range.length
        }
        if position < source.length { result.append(.init(id: result.count, text: source.substring(from: position), imageID: nil)) }
        return result
    }
}

/// Block structure for the native scratchpad preview; inline styling uses the shared renderer.
struct ScratchParagraph: Identifiable {
    enum Kind: Equatable { case body, heading(Int), code, quote }
    let id: Int
    let kind: Kind
    let text: String
    static func parse(_ source: String) -> [ScratchParagraph] {
        var result: [ScratchParagraph] = [], lines: [String] = []
        var fence: String?
        func flush(_ kind: Kind = .body) {
            guard !lines.isEmpty else { return }
            result.append(.init(id: result.count, kind: kind, text: lines.joined(separator: "\n")))
            lines.removeAll()
        }
        for line in source.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let active = fence {
                if trimmed.hasPrefix(active) { flush(.code); fence = nil } else { lines.append(line) }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush(); fence = String(trimmed.prefix(3))
            } else {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if (1...6).contains(hashes), trimmed.dropFirst(hashes).first == " " {
                    flush(); result.append(.init(id: result.count, kind: .heading(hashes), text: String(trimmed.dropFirst(hashes+1))))
                } else if trimmed.hasPrefix("> ") {
                    flush(); result.append(.init(id: result.count, kind: .quote, text: String(trimmed.dropFirst(2))))
                } else if trimmed.isEmpty { flush() }
                else { lines.append(line) }
            }
        }
        flush(fence == nil ? .body : .code)
        return result
    }
}
