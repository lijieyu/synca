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
