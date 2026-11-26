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
