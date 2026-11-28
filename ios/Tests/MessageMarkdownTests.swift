import AppKit

@main
struct MessageMarkdownTests {
    struct Fixture: Decodable {
        let id: String; let source: String; let contains: [String]; let types: [String]; let taskCount: Int; let plain: Bool?
    }
    @MainActor static func main() async throws {
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let parser = MarkdownParser.shared
        for fixture in fixtures {
            let document = parser.parse(fixture.source)
            let nodes = document.children.flatMap(\.descendants)
            let rendered = MessageMarkdownRenderer.render(document: document, baseColor: .labelColor)
            for text in fixture.contains { precondition(rendered.string.contains(text), "\(fixture.id): missing \(text)") }
            for type in fixture.types { precondition(nodes.contains { $0.type == type }, "\(fixture.id): missing \(type)") }
            let tasks = nodes.filter { $0.taskOffset != nil }
            precondition(tasks.count == fixture.taskCount, fixture.id)
            if let plain = fixture.plain { precondition(document.plain == plain, fixture.id) }
            if document.plain { precondition(rendered.string == fixture.source, "Plain whitespace must survive") }
            for task in tasks {
                let offset = task.taskOffset!
                let toggled = parser.toggleTask(fixture.source, offset: offset)!
                let before = Array(fixture.source.utf16), after = Array(toggled.utf16)
                precondition(before.count == after.count)
                precondition(zip(before, after).filter { $0 != $1 }.count == 1, "Only bracket middle changes")
                precondition(parser.parse(toggled).children.flatMap(\.descendants).first { $0.taskOffset == offset }?.checked != task.checked)
                var expected = before
                if expected[offset] == 88 { expected[offset] = 120 }
                precondition(parser.toggleTask(toggled, offset: offset) == String(decoding: expected, as: UTF16.self))
            }
        }
        let inline = MessageMarkdownRenderer.render("**bold** *italic* ~~strike~~ <u>under</u> `mono` [site](https://example.com)", baseColor: .secondaryLabelColor)
        func attr(_ key: NSAttributedString.Key, _ text: String) -> Any? { inline.attribute(key, at: (inline.string as NSString).range(of: text).location, effectiveRange: nil) }
        precondition((attr(.font, "bold") as! NSFont).fontDescriptor.symbolicTraits.contains(.bold))
        precondition((attr(.font, "italic") as! NSFont).fontDescriptor.symbolicTraits.contains(.italic))
        precondition(attr(.strikethroughStyle, "strike") as? Int == NSUnderlineStyle.single.rawValue)
        precondition(attr(.underlineStyle, "under") as? Int == NSUnderlineStyle.single.rawValue)
        precondition((attr(.font, "mono") as! NSFont).isFixedPitch)
        precondition(attr(.link, "site") != nil)
        for source in ["`![](synca-image:01234567-0123-0123-0123-012345678901)`", "```\n![](synca-image:01234567-0123-0123-0123-012345678901)\n```"] {
            precondition(parser.parse(source).children.flatMap(\.descendants).allSatisfy { $0.ownedImageID == nil })
        }
        precondition(parser.toggleTask("- [ ] a", offset: 0) == nil)
        let unsafe = MessageMarkdownRenderer.render("[bad](javascript:alert) <script>alert(1)</script>", baseColor: .labelColor)
        unsafe.enumerateAttribute(.link, in: NSRange(location: 0, length: unsafe.length)) { value, _, _ in precondition(value == nil) }
        for plain in ["a &amp; b", #"a\_b"#, "  ordinary  text\n\n\nend\n", "snake_case_name"] {
            precondition(MessageMarkdownRenderer.render(plain, baseColor: .labelColor).string == plain)
        }
        let upper = "- [X] first\n- [X] second"
        let upperOffsets = parser.parse(upper).children.flatMap(\.descendants).compactMap(\.taskOffset)
        let once = parser.toggleTask(upper, offset: upperOffsets[0])!
        precondition(once == "- [ ] first\n- [X] second")
        for encodedImage in [
            "![](synca-image&#58;11111111-1111-4111-8111-111111111111)",
            #"![](synca-image\:11111111-1111-4111-8111-111111111111)"#,
            "![](synca-image:&#49;1111111-1111-4111-8111-111111111111)",
            "![owned][asset]\n\n[asset]: synca-image&#58;11111111-1111-4111-8111-111111111111"
        ] {
            precondition(MarkdownImageCandidate.containsImageSyntax(encodedImage), "Encoded owned-image URL must reach the asynchronous AST ownership check")
            precondition(parser.parse(encodedImage).children.flatMap(\.descendants).contains { $0.ownedImageID == "11111111-1111-4111-8111-111111111111" })
        }
        let missing = MarkdownParser(resourceURL: nil)
        let raw = "# Preserve **raw**\n\n\t<script>"
        precondition(MessageMarkdownRenderer.render(document: missing.parse(raw), baseColor: .labelColor).string == raw)
        let nested = MessageMarkdownRenderer.render("- parent\n  - child", baseColor: .labelColor)
        let parentStyle = nested.attribute(.paragraphStyle, at: (nested.string as NSString).range(of: "parent").location, effectiveRange: nil) as! NSParagraphStyle
        let childStyle = nested.attribute(.paragraphStyle, at: (nested.string as NSString).range(of: "child").location, effectiveRange: nil) as! NSParagraphStyle
        precondition(childStyle.headIndent > parentStyle.headIndent, "Nested list preview retains hanging indentation")
        let longPlain = String(repeating: "保持原样 English 👋\n", count: 10000)
        precondition(MessageMarkdownRenderer.render(longPlain, baseColor: .labelColor).string == longPlain)
        let tail = MessageMarkdownRenderer.render(String(repeating: "前面的段落\n", count: 100) + "**目标关键词**", baseColor: .labelColor)
        precondition(MessageMarkdownRenderer.matchOffset(tail, text: "目标关键词", width: 300) > 1000)
        precondition(MessageMarkdownRenderer.overflows(tail, width: 300, maximumLines: 6))
        let manyTasks = String(repeating: "- [ ] x\n", count: 31_250)
        let started = Date()
        let heartbeat = Task { @MainActor in try? await Task.sleep(for: .milliseconds(25)); return Date() }
        let largeDocument = await parser.parseAsync(manyTasks)
        let duration = Date().timeIntervalSince(started)
        let heartbeatDelay = await heartbeat.value.timeIntervalSince(started)
        precondition(largeDocument.children.flatMap(\.descendants).filter { $0.taskOffset != nil }.count == 31_250)
        precondition(heartbeatDelay < max(0.75, duration * 0.8), "Large Markdown parsing must not block the UI actor")
        let lastOffset = largeDocument.children.flatMap(\.descendants).compactMap(\.taskOffset).last!
        let toggledLarge = await parser.toggleTaskAsync(manyTasks, offset: lastOffset)!
        precondition(toggledLarge.hasSuffix("- [x] x\n") && toggledLarge.utf16.count == 250_000)
        print(String(format: "Large corpus: 250000 UTF-16 units / 31250 tasks parsed in %.3fs; UI heartbeat %.3fs", duration, heartbeatDelay))
        print("PASS: \(fixtures.count) shared fixtures, UTF-16 task patches, native traits, owned images, safe links, raw fallback and long text")
    }
}
