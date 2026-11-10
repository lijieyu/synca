import Foundation

struct MessageSearchResult: Identifiable, Sendable {
    let message: SyncaMessage
    let rank: Int
    let excerpt: String
    var id: String { message.id }
}

/// Account-local, content-keyed tokens. The actor keeps transliteration off the UI actor
/// and never retains messages removed from the caller's current snapshot.
actor MessageSearchIndex {
    private struct Field {
        let raw: String
        let pinyin: String
        let initials: String

        init(_ source: String) {
            raw = MessageSearchIndex.normalized(source)
            var full = "", abbreviated = "", run = "", runIsHan = false
            func appendRun() {
                guard !run.isEmpty else { return }
                let latin = MessageSearchIndex.romanized(runIsHan ? (run.applyingTransform(.toLatin, reverse: false) ?? run) : run)
                full += latin.filter { !$0.isWhitespace && $0 != "'" }
                if runIsHan {
                    abbreviated += latin.split(whereSeparator: { $0.isWhitespace }).compactMap(\.first).map(String.init).joined()
                } else {
                    // Embedded filenames/English words stay intact, matching the Web index.
                    abbreviated += latin.filter { !$0.isWhitespace && $0 != "'" }
                }
            }
            for character in source {
                let han = character.unicodeScalars.contains {
                    (0x3400...0x9fff).contains($0.value) || (0xf900...0xfaff).contains($0.value)
                        || (0x20000...0x323af).contains($0.value)
                }
                if !run.isEmpty && han != runIsHan { appendRun(); run = "" }
                runIsHan = han
                run.append(character)
            }
            appendRun()
            pinyin = full
            initials = abbreviated
        }
    }

    private struct Entry {
        let userID: String
        let text: String
        let filename: String
        let fields: [Field]
        let createdAt: Date
    }
    private var entries: [String: Entry] = [:]
    private let fractionalDate = ISO8601DateFormatter()
    private let plainDate = ISO8601DateFormatter()

    init() {
        fractionalDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func search(_ messages: [SyncaMessage], query: String, categoryID: String? = nil) -> [MessageSearchResult] {
        let liveIDs = Set(messages.filter { !$0.isDeleted }.map(\.id))
        entries = entries.filter { liveIDs.contains($0.key) }
        let normalizedQuery = Self.normalized(query).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return [] }
        let latinQuery = Self.romanized(query).filter { !$0.isWhitespace && $0 != "\'" }
        let usePinyin = latinQuery.count >= 2 && latinQuery.unicodeScalars.allSatisfy {
            (97...122).contains($0.value)
        }
        var matches: [(MessageSearchResult, Date)] = []
        for message in messages {
            guard !Task.isCancelled else { return [] }
            guard !message.isDeleted, categoryID == nil || message.categoryId == categoryID else { continue }
            let text = message.textContent ?? "", filename = message.fileName ?? ""
            let entry: Entry
            if let cached = entries[message.id], cached.userID == message.userId,
               cached.text == text, cached.filename == filename {
                entry = cached
            } else {
                entry = Entry(userID: message.userId, text: text, filename: filename,
                              fields: [text, filename].filter { !$0.isEmpty }.map(Field.init),
                              createdAt: fractionalDate.date(from: message.createdAt)
                                  ?? plainDate.date(from: message.createdAt) ?? .distantPast)
                entries[message.id] = entry
            }
            let rank: Int
            if entry.fields.contains(where: { $0.raw.contains(normalizedQuery) }) { rank = 0 }
            else if usePinyin && entry.fields.contains(where: { $0.pinyin.contains(latinQuery) }) { rank = 1 }
            else if usePinyin && entry.fields.contains(where: { $0.initials.contains(latinQuery) }) { rank = 2 }
            else { continue }
            matches.append((MessageSearchResult(message: message, rank: rank,
                                                excerpt: Self.excerpt(text.isEmpty ? filename : text, query: query)), entry.createdAt))
        }
        return matches.sorted {
            if $0.0.rank != $1.0.rank { return $0.0.rank < $1.0.rank }
            if $0.1 != $1.1 { return $0.1 > $1.1 }
            return $0.0.id > $1.0.id
        }.map(\.0)
    }

    private static func romanized(_ value: String) -> String {
        let scalars = value.lowercased().decomposedStringWithCanonicalMapping.unicodeScalars
        var output = String.UnicodeScalarView()
        for scalar in scalars {
            if scalar.value == 0x0308, output.last?.value == 0x0075 {
                output.removeLast()
                output.append(UnicodeScalar(0x0076)!)
            } else { output.append(scalar) }
        }
        return normalized(String(output))
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                      locale: Locale(identifier: "en_US_POSIX")).lowercased()
    }

    private static func excerpt(_ value: String, query: String) -> String {
        let range = value.range(of: query.trimmingCharacters(in: .whitespacesAndNewlines),
                               options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive])
        let start = range.map { value.index($0.lowerBound, offsetBy: -32, limitedBy: value.startIndex) ?? value.startIndex } ?? value.startIndex
        let end = value.index(start, offsetBy: 160, limitedBy: value.endIndex) ?? value.endIndex
        return (start == value.startIndex ? "" : "…") + String(value[start..<end]) + (end == value.endIndex ? "" : "…")
    }
}
