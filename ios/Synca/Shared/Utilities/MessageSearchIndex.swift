import Foundation

struct MessageSearchResult: Identifiable, Sendable {
    let message: SyncaMessage
    let rank: Int
    let excerpt: String
    /// Half-open UTF-16 offsets into excerpt and message.fileName, respectively.
    let excerptRanges: [Range<Int>]
    let filenameRanges: [Range<Int>]
    let matchedText: String?
    var id: String { message.id }
}

/// Account-local, content-keyed tokens. The actor keeps transliteration off the UI actor
/// and never retains messages removed from the caller's current snapshot.
actor MessageSearchIndex {
    private struct Token {
        var value = ""
        var map: [Range<Int>] = []
        mutating func append(_ value: String, source: Range<Int>, storeMap: Bool) {
            self.value += value
            if storeMap { map.append(contentsOf: repeatElement(source, count: value.utf16.count)) }
        }
        func matches(_ query: String) -> [Range<Int>] {
            let source = value as NSString
            var result: [Range<Int>] = [], offset = 0
            while offset < source.length {
                let found = source.range(of: query, range: NSRange(location: offset, length: source.length - offset))
                guard found.location != NSNotFound else { break }
                result.append(map[found.location].lowerBound..<map[NSMaxRange(found) - 1].upperBound)
                offset = found.location + 1
            }
            return result
        }
    }
    private struct Field {
        var raw = Token(), pinyin = Token(), initials = Token()
        init(_ source: String, mapped: Bool = false) {
            var characters: [(String, Range<Int>, Bool)] = [], offset = 0
            for character in source {
                let value = String(character), end = offset + value.utf16.count
                let han = character.unicodeScalars.contains {
                    (0x3400...0x9fff).contains($0.value) || (0xf900...0xfaff).contains($0.value)
                        || (0x20000...0x323af).contains($0.value)
                }
                characters.append((value, offset..<end, han))
                raw.append(MessageSearchIndex.normalized(value), source: offset..<end, storeMap: mapped)
                offset = end
            }
            var index = 0
            while index < characters.count {
                if !characters[index].2 {
                    let item = characters[index]
                    let latin = MessageSearchIndex.romanized(item.0).filter { !$0.isWhitespace && $0 != "'" }
                    pinyin.append(latin, source: item.1, storeMap: mapped)
                    initials.append(latin, source: item.1, storeMap: mapped)
                    index += 1
                    continue
                }
                var end = index + 1
                while end < characters.count && characters[end].2 { end += 1 }
                let run = characters[index..<end].map { $0.0 }.joined()
                let syllables = MessageSearchIndex.romanized(run.applyingTransform(.toLatin, reverse: false) ?? run)
                    .split(whereSeparator: { $0.isWhitespace }).map(String.init)
                for cursor in index..<end {
                    let item = characters[cursor]
                    let syllable = syllables.count == end - index ? syllables[cursor - index]
                        : MessageSearchIndex.romanized(item.0.applyingTransform(.toLatin, reverse: false) ?? item.0)
                    let latin = syllable.filter { !$0.isWhitespace && $0 != "'" }
                    pinyin.append(latin, source: item.1, storeMap: mapped)
                    initials.append(latin.first.map(String.init) ?? "", source: item.1, storeMap: mapped)
                }
                index = end
            }
        }
        func matches(raw query: String, latin: String, phonetic: Bool) -> [Range<Int>] {
            var ranges = raw.matches(query)
            if phonetic { ranges += pinyin.matches(latin) + initials.matches(latin) }
            ranges.sort { $0.lowerBound == $1.lowerBound ? $0.upperBound < $1.upperBound : $0.lowerBound < $1.lowerBound }
            var merged: [Range<Int>] = []
            for range in ranges {
                if let last = merged.last, range.lowerBound <= last.upperBound {
                    merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, range.upperBound)
                } else { merged.append(range) }
            }
            return merged
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
    // Keep the corpus index lightweight; only recently previewed fields need maps.
    private var mappedFields: [String: Field] = [:]
    private var mappedOrder: [String] = []
    private let maxMappedFields = 32
    private let maxMappedCharacters = 200_000

    private func mappedField(_ source: String) -> Field {
        if let cached = mappedFields[source] {
            mappedOrder.removeAll { $0 == source }
            mappedOrder.append(source)
            return cached
        }
        let field = Field(source, mapped: true)
        mappedFields[source] = field
        mappedOrder.append(source)
        var characters = mappedOrder.reduce(0) { $0 + $1.utf16.count }
        while mappedOrder.count > maxMappedFields || characters > maxMappedCharacters {
            let oldest = mappedOrder.removeFirst()
            characters -= oldest.utf16.count
            mappedFields.removeValue(forKey: oldest)
        }
        return field
    }
    private let fractionalDate = ISO8601DateFormatter()
    private let plainDate = ISO8601DateFormatter()

    init() {
        fractionalDate.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    func search(_ messages: [SyncaMessage], query: String, categoryID: String? = nil) -> [MessageSearchResult] {
        let liveIDs = Set(messages.filter { !$0.isDeleted }.map(\.id))
        entries = entries.filter { liveIDs.contains($0.key) }
        let liveText = Set(messages.filter { !$0.isDeleted }.flatMap { [$0.textContent ?? "", $0.fileName ?? ""] })
        mappedFields = mappedFields.filter { liveText.contains($0.key) }
        mappedOrder.removeAll { !liveText.contains($0) }
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
                              fields: [text, filename].map { Field($0) },
                              createdAt: fractionalDate.date(from: message.createdAt)
                                  ?? plainDate.date(from: message.createdAt) ?? .distantPast)
                entries[message.id] = entry
            }
            let rank: Int
            if entry.fields.contains(where: { $0.raw.value.contains(normalizedQuery) }) { rank = 0 }
            else if usePinyin && entry.fields.contains(where: { $0.pinyin.value.contains(latinQuery) }) { rank = 1 }
            else if usePinyin && entry.fields.contains(where: { $0.initials.value.contains(latinQuery) }) { rank = 2 }
            else { continue }
            let textRanges = mappedField(text).matches(raw: normalizedQuery, latin: latinQuery, phonetic: usePinyin)
            let filenameRanges = mappedField(filename).matches(raw: normalizedQuery, latin: latinQuery, phonetic: usePinyin)
            let preview = Self.excerpt(text.isEmpty ? filename : text, ranges: text.isEmpty ? filenameRanges : textRanges)
            matches.append((MessageSearchResult(message: message, rank: rank, excerpt: preview.text,
                                                excerptRanges: preview.ranges, filenameRanges: filenameRanges,
                                                matchedText: textRanges.first.flatMap { Range(NSRange(location: $0.lowerBound, length: $0.count), in: text) }.map { String(text[$0]) }), entry.createdAt))
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

    private static func excerpt(_ source: String, ranges sourceRanges: [Range<Int>]) -> (text: String, ranges: [Range<Int>]) {
        // Compact line breaks before slicing, retaining offsets into the displayed text.
        var value = ""
        var offsets = [Int](repeating: 0, count: source.utf16.count + 1)
        var sourceOffset = 0
        var outputOffset = 0
        var previousWhitespace = false
        for character in source {
            let original = String(character)
            let whitespace = character.isWhitespace
            let replacement = whitespace ? (previousWhitespace ? "" : " ") : original
            for unit in 0..<original.utf16.count {
                offsets[sourceOffset + unit] = outputOffset + min(unit, replacement.utf16.count)
            }
            value += replacement
            sourceOffset += original.utf16.count
            outputOffset += replacement.utf16.count
            offsets[sourceOffset] = outputOffset
            previousWhitespace = whitespace
        }
        let ranges = sourceRanges.compactMap { range -> Range<Int>? in
            let lower = offsets[range.lowerBound], upper = offsets[range.upperBound]
            return lower < upper ? lower..<upper : nil
        }

        if value.count <= 160 { return (value, ranges) }
        let match = ranges.first.flatMap { Range(NSRange(location: $0.lowerBound, length: $0.count), in: value) }
        let start = match.map { value.index($0.lowerBound, offsetBy: -12, limitedBy: value.startIndex) ?? value.startIndex } ?? value.startIndex
        let end = value.index(start, offsetBy: 160, limitedBy: value.endIndex) ?? value.endIndex
        let offset = start.utf16Offset(in: value), endOffset = end.utf16Offset(in: value)
        let prefix = start == value.startIndex ? "" : "…"
        let mapped = ranges.compactMap { range -> Range<Int>? in
            let lower = max(range.lowerBound, offset), upper = min(range.upperBound, endOffset)
            guard lower < upper else { return nil }
            return (lower - offset + prefix.utf16.count)..<(upper - offset + prefix.utf16.count)
        }
        return (prefix + String(value[start..<end]) + (end == value.endIndex ? "" : "…"), mapped)
    }
}
