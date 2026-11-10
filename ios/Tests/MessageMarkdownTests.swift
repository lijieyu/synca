import AppKit

@main
struct MessageMarkdownTests {
    @MainActor static func main() {
        let source = "1. **标题**\n   - 子项目 `code`\n> 引用\n[官网](https://example.com) https://example.org"
        let rendered = MessageMarkdownRenderer.render(source, baseColor: .labelColor)
        precondition(rendered.string == "1.\t标题\n•\t子项目 code\n│\t引用\n官网 https://example.org", "Render compact lists, quotes and inline formatting")
        let title = (rendered.string as NSString).range(of: "标题").location
        let font = rendered.attribute(.font, at: title, effectiveRange: nil) as! NSFont
        precondition(font.fontDescriptor.symbolicTraits.contains(.bold), "Bold must survive native attributed rendering")
        let code = (rendered.string as NSString).range(of: "code").location
        precondition((rendered.attribute(.font, at: code, effectiveRange: nil) as! NSFont).isFixedPitch)
        let nested = (rendered.string as NSString).range(of: "子项目").location
        let style = rendered.attribute(.paragraphStyle, at: nested, effectiveRange: nil) as! NSParagraphStyle
        precondition(style.firstLineHeadIndent > 0 && style.headIndent > style.firstLineHeadIndent)
        for label in ["官网", "https://example.org"] {
            precondition(rendered.attribute(.link, at: (rendered.string as NSString).range(of: label).location, effectiveRange: nil) != nil)
        }
        let plain = "普通 English 👨‍👩‍👧‍👦\n\n第二段\n"
        let unchanged = MessageMarkdownRenderer.render(plain, baseColor: .secondaryLabelColor)
        precondition(unchanged.string == plain, "Plain text whitespace must survive")
        precondition((unchanged.attribute(.font, at: 0, effectiveRange: nil) as! NSFont) == NSFont.preferredFont(forTextStyle: .body))
        precondition((unchanged.attribute(.foregroundColor, at: 0, effectiveRange: nil) as! NSColor) == .secondaryLabelColor)
        precondition(MessageMarkdownRenderer.render("**未完成", baseColor: .labelColor).string == "**未完成")
        for text in ["a &amp; b", #"a\_b"#, "  ordinary  text\n\n\nend\n", "snake_case_name"] {
            precondition(MessageMarkdownRenderer.render(text, baseColor: .labelColor).string == text, "Plain records must bypass Markdown decoding")
        }
        precondition(MessageMarkdownRenderer.render("a *b* c", baseColor: .labelColor).string == "a b c", "Italic detection matches Web")
        precondition(MessageMarkdownRenderer.render("1. a\n\n1. b", baseColor: .labelColor).string == "1.\ta\n\n2.\tb", "Blank line must not reset ordered list")
        let fenced = "```swift\n- **literal**\n```"
        precondition(MessageMarkdownRenderer.render(fenced, baseColor: .labelColor).string == fenced)
        precondition(MessageMarkdownRenderer.render("![alt](https://example.com/image.png)", baseColor: .labelColor).string == "![alt](https://example.com/image.png)")
        let unsafe = MessageMarkdownRenderer.render("[bad](javascript:alert) [local](file:///tmp/test)", baseColor: .labelColor)
        unsafe.enumerateAttribute(.link, in: NSRange(location: 0, length: unsafe.length)) { value, _, _ in precondition(value == nil) }
        precondition(MessageMarkdownRenderer.render("1. first\n1. second", baseColor: .labelColor).string == "1.\tfirst\n2.\tsecond")
        let six = MessageMarkdownRenderer.render(Array(repeating: "- **项目**", count: 6).joined(separator: "\n"), baseColor: .labelColor)
        let seven = MessageMarkdownRenderer.render(Array(repeating: "- **项目**", count: 7).joined(separator: "\n"), baseColor: .labelColor)
        precondition(!MessageMarkdownRenderer.overflows(six, width: 300, maximumLines: 6))
        precondition(MessageMarkdownRenderer.overflows(seven, width: 300, maximumLines: 6))
        precondition(MessageMarkdownRenderer.overflows(MessageMarkdownRenderer.render("- " + String(repeating: "嵌套内容 ", count: 60), baseColor: .labelColor), width: 160, maximumLines: 6))
        let longPlain = String(repeating: "纯文本 English 👋 保持原样并正常换行。", count: 50)
        let plainRendered = MessageMarkdownRenderer.render(longPlain, baseColor: .labelColor)
        precondition(plainRendered.string == longPlain)
        precondition(MessageMarkdownRenderer.overflows(plainRendered, width: 300, maximumLines: 6))
        let wrapped = MessageMarkdownRenderer.render("  - " + String(repeating: "子项目内容 ", count: 30), baseColor: .labelColor)
        let storage = NSTextStorage(attributedString: wrapped)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 160, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        manager.ensureLayout(for: container)
        let paragraph = wrapped.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as! NSParagraphStyle
        var fragments = 0
        manager.enumerateLineFragments(forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)) { _, used, _, _, _ in
            if fragments > 0 { precondition(used.minX >= paragraph.headIndent - 1, "Wrapped nested lines retain hanging indentation") }
            fragments += 1
        }
        precondition(fragments > 1)
        print("PASS: native Markdown styles, nested lists, links, plain text, incomplete markup and rendered six-line overflow")
    }
}
