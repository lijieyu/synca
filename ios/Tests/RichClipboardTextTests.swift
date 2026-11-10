import AppKit

@main
struct RichClipboardTextTests {
    @MainActor static func main() {
        exit(run())
    }

    @MainActor private static func run() -> Int32 {
        var failures = 0
        func expect(_ actual: String?, _ expected: String?, _ name: String) {
            if actual != expected {
                failures += 1
                print("FAIL \(name): \(String(reflecting: actual)) != \(String(reflecting: expected))")
            }
        }
        func html(_ source: String, fallback: String = "fallback") -> String? {
            RichClipboardText.string(plainText: fallback, html: Data(source.utf8), rtf: nil)
        }
        expect(RichClipboardText.string(plainText: "  原文\n1. abc\t", html: nil, rtf: nil), "  原文\n1. abc\t", "plain text remains byte-for-byte")
        expect(html("<ul><li>First</li><li>第二项<ul><li>Child &amp; &#x1F600;</li></ul></li></ul>"), "- First\n- 第二项\n    - Child & 😀", "nested HTML list keeps structure")
        expect(html("<p>Before</p><ol start='3'><li><p>One</p><p>continued</p></li><li value='8'>Eight</li></ol><p>After</p>"), "Before\n3. One\n    continued\n8. Eight\nAfter", "ordered numbering and continuation")
        expect(html("<ul><li>A <strong>bold</strong> word<br>next</li><li>B</li></ul>"), "- A bold word\n    next\n- B", "inline tags and breaks")
        expect(html("<script>fetch('https://bad')</script><style>body{}</style><ul><li>Safe<img src='https://bad/a.png'></li></ul>"), "- Safe", "active elements never become content")
        expect(html("<p>ordinary <b>rich</b> text</p>", fallback: "plain fallback"), "plain fallback", "non-list HTML uses supplied plain text")
        expect(html("<ul><li>broken"), "fallback", "malformed list falls back without partial data loss")
        let codePlain = "Run this:\nif ready:\n    start()\n    finish()"
        expect(html("<ul><li>Run this:</li></ul><pre><code>if ready:\n    start()\n    finish()</code></pre>", fallback: codePlain), codePlain, "mixed code block retains original whitespace")
        let list = NSTextList(markerFormat: .decimal, options: 0)
        list.startingItemNumber = 4
        let style = NSMutableParagraphStyle()
        style.textLists = [list]
        let rich = NSAttributedString(string: "\t4.\tFour\n\t5.\tFive\n", attributes: [.paragraphStyle: style])
        let data = try! rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        expect(RichClipboardText.string(plainText: "Four\nFive", html: nil, rtf: data), "4. Four\n5. Five", "RTF metadata produces ordered markers without duplication")
        // Exercise the composer paste handler with an isolated clipboard.
        _ = NSApplication.shared
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let input = PasteAwareMacTextView()
        input.isRichText = false
        input.allowsUndo = true
        input.string = "Before selected after"
        input.setSelectedRange(NSRange(location: 7, length: 8))
        pasteboard.clearContents()
        pasteboard.setString("One\nTwo", forType: .string)
        pasteboard.setString("<ul><li>One</li><li>Two</li></ul>", forType: .html)
        input.pasteContents(from: pasteboard)
        expect(input.string, "Before - One\n- Two after", "composer paste replaces selection with plain Markdown")
        pasteboard.clearContents()
        pasteboard.setString("  plain\n\ttext  ", forType: .string)
        input.string = ""
        input.setSelectedRange(NSRange(location: 0, length: 0))
        input.pasteContents(from: pasteboard)
        expect(input.string, "  plain\n\ttext  ", "composer paste preserves plain whitespace")
        var pastedImage: Data?
        input.onPasteImage = { pastedImage = $0 }
        let imageData = Data([1, 2, 3])
        pasteboard.clearContents()
        pasteboard.setData(imageData, forType: .png)
        pasteboard.setString("<ul><li>Text</li></ul>", forType: .html)
        input.pasteContents(from: pasteboard)
        expect(pastedImage == imageData ? "image" : nil, "image", "image paste keeps its existing priority")
        if failures > 0 { return 1 }
        print("Rich clipboard tests passed")
        return 0
    }
}
