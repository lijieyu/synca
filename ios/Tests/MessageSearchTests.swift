import Foundation

@main
struct MessageSearchTests {
    static func record(_ id: String, _ text: String, file: String? = nil, category: String = "work", done: Bool = false, deleted: Bool = false, date: String = "2026-11-10T10:00:00Z") -> SyncaMessage {
        SyncaMessage(id: id, userId: "fixture", type: file == nil ? .text : .file,
                     textContent: text, fileName: file, categoryId: category,
                     isCleared: done, isDeleted: deleted, createdAt: date, updatedAt: date)
    }
    static func main() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let parser = ISO8601DateFormatter()
        let now = parser.date(from: "2026-01-01T01:00:00Z")!
        for localeID in ["en_US", "zh_Hans_CN", "zh_Hant_TW"] {
            let locale = Locale(identifier: localeID)
            let time = DateFormatter()
            time.locale = locale; time.timeZone = calendar.timeZone
            time.setLocalizedDateFormatFromTemplate("jm")
            precondition(SyncaMessage.formatRelativeDate(now, now: now, calendar: calendar, locale: locale) == time.string(from: now))
            let yesterday = parser.date(from: "2025-12-31T01:00:00Z")!
            let previous = SyncaMessage.formatRelativeDate(yesterday, now: now, calendar: calendar, locale: locale)
            precondition(previous == String(format: String(syncaLocalized: "message.date.yesterday"), time.string(from: yesterday)), "Yesterday takes precedence over year boundary")
            for stamp in ["2026-01-03T01:00:00Z", "2025-12-30T01:00:00Z"] {
                let date = parser.date(from: stamp)!
                let day = DateFormatter()
                day.locale = locale; day.timeZone = calendar.timeZone
                day.setLocalizedDateFormatFromTemplate(stamp.hasPrefix("2026") ? "Md" : "yMd")
                let expected = "\(day.string(from: date)) \(time.string(from: date))"
                precondition(SyncaMessage.formatRelativeDate(date, now: now, calendar: calendar, locale: locale) == expected, "Current year omits year; previous year includes it; future dates do not show weekday")
            }
            let localToday = parser.date(from: "2025-12-31T16:30:00Z")!
            precondition(SyncaMessage.formatRelativeDate(localToday, now: now, calendar: calendar, locale: locale) == time.string(from: localToday), "Day boundary uses local time zone")
        }
        let index = MessageSearchIndex()
        let rows = [record("a", "准备周五的沟通提纲"), record("b", "面试准备清单", done: true),
                    record("c", "", file: "面试计划.PDF", category: "life"), record("d", "面试删除", deleted: true),
                    record("e", "mianshi notes", date: "2026-11-09T10:00:00Z")]
        func ids(_ query: String, category: String? = nil) async -> [String] {
            await index.search(rows, query: query, categoryID: category).map(\.id)
        }
        let literal = await ids("沟通")
        precondition(literal == ["a"], "Visible feed records must be searchable")
        let chinese = await ids("面试")
        precondition(Set(chinese) == ["b", "c"], "Completed and filename included; deleted excluded")
        let pinyin = await ids("mianshi")
        precondition(pinyin == ["e", "c", "b"], "Raw ranks before transliteration, stable ID descending tie")
        let initials = await ids("mszb")
        precondition(initials == ["b"], "Consecutive initials")
        let nonconsecutive = await ids("msqd")
        precondition(nonconsecutive.isEmpty, "Do not match arbitrary skipping initials")
        let filename = await ids("pdf")
        precondition(filename == ["c"])
        let scoped = await ids("面试", category: "life")
        precondition(scoped == ["c"])
        let blank = await ids("  \n")
        precondition(blank.isEmpty)
        let single = await ids("z")
        precondition(single.allSatisfy { $0 != "b" }, "One letter must not match initials inside a syllable")
        let updated = await index.search([record("b", "新的任务")], query: "面试")
        precondition(updated.isEmpty, "Edited content invalidates cached tokens")
        let removed = await index.search([], query: "新的任务")
        precondition(removed.isEmpty, "No stale rows after reset")
        let traditional = await index.search([record("t", "面試準備")], query: "mianshi")
        precondition(traditional.map(\.id) == ["t"])
        let width = await index.search([record("w", "Résumé ＡＰＰ.PDF")], query: "resume app.pdf")
        precondition(width.map(\.id) == ["w"])
        let shortText = String(repeating: "前文", count: 30) + "目标关键词"
        let short = await index.search([record("short", shortText)], query: "关键词")
        precondition(short.first?.excerpt == shortText, "Short excerpts retain their full beginning")
        let multiline = await index.search([record("multiline", String(repeating: "前文\n", count: 80) + "目标关键词")], query: "关键词")
        precondition(multiline[0].excerptRanges[0].lowerBound <= 13, "Long excerpt hit stays close to the beginning of the three-line preview")
        precondition(!multiline[0].excerpt.contains("\n"), "Multiline previews keep compact context")
        let multilineRange = multiline[0].excerptRanges[0]
        precondition((multiline[0].excerpt as NSString).substring(with: NSRange(location: multilineRange.lowerBound, length: multilineRange.count)) == "关键词", "Compacted whitespace retains Unicode highlight offsets")
        let many = await index.search((0..<600).map { record("count-\($0)", "match") }, query: "match")
        precondition(many.count == 600, "Result count includes every match")
        let tail = await index.search([record("long", String(repeating: "记录。", count: 3000) + "目标关键词")], query: "关键词")
        precondition(tail.first?.excerpt.contains("关键词") == true)
        precondition(tail.first!.excerpt.count <= 180)
        let mixed = await index.search([record("m", "面试Synca准备")], query: "mianshisynca")
        precondition(mixed.map(\.id) == ["m"])
        for query in ["lvyou", "lüyou"] {
            let travel = await index.search([record("travel", "旅游计划")], query: query)
            precondition(travel.map(\.id) == ["travel"], "Umlaut and v both search travel")
        }
        let mixedInitials = await index.search([record("m", "面试 Synca 准备")], query: "mssyncazb")
        precondition(mixedInitials.map(\.id) == ["m"], "Keep embedded Latin words in mixed initials")
        for query in ["mianshi", "ms", "面试"] {
            let highlighted = await index.search([record("h", String(repeating: "😀前文。", count: 200) + "面试安排，面试准备")], query: query)
            let result = highlighted[0]
            let hits = result.excerptRanges.map { (result.excerpt as NSString).substring(with: NSRange(location: $0.lowerBound, length: $0.count)) }
            precondition(hits == ["面试", "面试"], "Late phonetic matches and repeated hits use original UTF16 offsets")
            precondition(result.excerpt.hasPrefix("…"))
        }
        let accents = await index.search([record("a", "😀Cafe\u{0301} ＡＢＣ")], query: "cafe")
        let accentRange = accents[0].excerptRanges[0]
        precondition((accents[0].excerpt as NSString).substring(with: NSRange(location: accentRange.lowerBound, length: accentRange.count)) == "Cafe\u{0301}")
        let named = await index.search([record("f", "caption", file: "😀会议纪要.pdf")], query: "hyjy")
        precondition(named[0].filenameRanges == [2..<6])
        print("PASS native search: literal, pinyin, initials, scope, deleted/completed, stable rank, filename, edits/reset, traditional, accents/width, long excerpt, mixed Latin")
    }
}
