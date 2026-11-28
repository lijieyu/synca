import Foundation
import JavaScriptCore

struct MarkdownNode: Decodable, Sendable {
    let type: String
    var children: [MarkdownNode]?
    var value: String?
    var depth: Int?
    var ordered: Bool?
    var start: Int?
    var checked: Bool?
    var taskOffset: Int?
    var align: [String?]?
    var url: String?
    var title: String?
    var alt: String?
    var lang: String?
    var source: String?
    var position: Position?
    struct Position: Decodable, Sendable {
        let start: Point
        let end: Point
        struct Point: Decodable, Sendable { let offset: Int }
    }
    var text: String {
        if type == "break" { return "\n" }
        if type == "image" { return source ?? alt ?? "" }
        return value ?? (children ?? []).map(\.text).joined()
    }
    var ownedImageID: String? {
        guard type == "image", let url, url.lowercased().hasPrefix("synca-image:"),
              let uuid = UUID(uuidString: String(url.dropFirst("synca-image:".count))) else { return nil }
        return uuid.uuidString.lowercased()
    }
    var descendants: [MarkdownNode] { [self] + (children ?? []).flatMap(\.descendants) }
}

enum MarkdownImageCandidate {
    static func containsImageSyntax(_ source: String) -> Bool {
        // Destinations may use CommonMark escapes/entities or references. This is
        // only a cheap candidate gate; the async parsed AST authorizes asset reads.
        source.contains("![")
    }
}

struct MarkdownDocument: Decodable, Sendable {
    let version: Int
    let type: String
    let plain: Bool
    let children: [MarkdownNode]
}

/// All entry points run on one actor: JavaScriptCore contexts are never shared across threads.
/// Only the trusted bundled parser is evaluated; user content is passed as a function argument.
@MainActor
final class MarkdownParser {
    static let shared = MarkdownParser(resourceURL: Bundle.main.url(forResource: "markdown-parser", withExtension: "js"))
    private let context: JSContext?
    private let cache = NSCache<NSString, CachedDocument>()
    private let resourceURL: URL?
    private var pending: [String: Task<MarkdownDocument, Never>] = [:]
    private static let worker = MarkdownParserWorker()
    private final class CachedDocument: NSObject {
        let value: MarkdownDocument
        init(_ value: MarkdownDocument) { self.value = value }
    }
    init(resourceURL: URL?) {
        self.resourceURL = resourceURL
        cache.countLimit = 128
        cache.totalCostLimit = 8 * 1024 * 1024
        if let resourceURL, let script = try? String(contentsOf: resourceURL, encoding: .utf8), let context = JSContext() {
            context.evaluateScript(script)
            self.context = context.exception == nil ? context : nil
        } else { context = nil }
    }
    func parse(_ source: String) -> MarkdownDocument {
        if let result = cache.object(forKey: source as NSString) { return result.value }
        context?.exception = nil
        let value = context?.objectForKeyedSubscript("SyncaMarkdown")?.invokeMethod("parseJSON", withArguments: [source])
        let parsed = value?.toString()?.data(using: .utf8).flatMap { try? JSONDecoder().decode(MarkdownDocument.self, from: $0) }
        let document: MarkdownDocument
        if context?.exception == nil, let parsed, parsed.version == 1, parsed.type == "root", !parsed.plain { document = parsed }
        else {
            document = MarkdownDocument(version: 1, type: "root", plain: true,
                children: [MarkdownNode(type: "paragraph", children: [MarkdownNode(type: "text", value: source)])])
        }
        cache.setObject(CachedDocument(document), forKey: source as NSString, cost: source.utf16.count * 8)
        return document
    }
    func cachedDocument(_ source: String) -> MarkdownDocument? { cache.object(forKey: source as NSString)?.value }
    func parseAsync(_ source: String) async -> MarkdownDocument {
        if let cached = cachedDocument(source) { return cached }
        if let task = pending[source] { return await task.value }
        let task = Task { [resourceURL] in
            let parsed = await Self.worker.parse(source, resourceURL: resourceURL)
            let document = parsed.flatMap { $0.version == 1 && $0.type == "root" && !$0.plain ? $0 : nil }
                ?? MarkdownDocument(version: 1, type: "root", plain: true,
                    children: [MarkdownNode(type: "paragraph", children: [MarkdownNode(type: "text", value: source)])])
            cache.setObject(CachedDocument(document), forKey: source as NSString, cost: source.utf16.count * 8)
            pending[source] = nil
            return document
        }
        pending[source] = task
        return await task.value
    }
    func toggleTaskAsync(_ source: String, offset: Int) async -> String? {
        guard source.utf16.count > 32_000 else { return toggleTask(source, offset: offset) }
        return await Self.worker.toggle(source, offset: offset, resourceURL: resourceURL)
    }
    func toggleTask(_ source: String, offset: Int) -> String? {
        guard offset >= 0 else { return nil }
        context?.exception = nil
        guard let result = context?.objectForKeyedSubscript("SyncaMarkdown")?.invokeMethod("toggleTask", withArguments: [source, offset]),
              context?.exception == nil, !result.isNull, !result.isUndefined else { return nil }
        return result.toString()
    }
}

/// Large documents parse off the UI actor. A serial actor owns the JS context and
/// transfers only decoded Sendable value types back to native rendering.
private actor MarkdownParserWorker {
    private var context: JSContext?
    private var loadedURL: URL?
    func toggle(_ source: String, offset: Int, resourceURL: URL?) -> String? {
        if context == nil || loadedURL != resourceURL { _ = parse("", resourceURL: resourceURL) }
        context?.exception = nil
        guard let result = context?.objectForKeyedSubscript("SyncaMarkdown")?.invokeMethod("toggleTask", withArguments: [source, offset]),
              context?.exception == nil, !result.isNull, !result.isUndefined else { return nil }
        return result.toString()
    }
    func parse(_ source: String, resourceURL: URL?) -> MarkdownDocument? {
        if context == nil || loadedURL != resourceURL {
            guard let resourceURL, let script = try? String(contentsOf: resourceURL, encoding: .utf8), let next = JSContext() else { return nil }
            next.evaluateScript(script)
            guard next.exception == nil else { return nil }
            context = next; loadedURL = resourceURL
        }
        context?.exception = nil
        guard let json = context?.objectForKeyedSubscript("SyncaMarkdown")?.invokeMethod("parseJSON", withArguments: [source])?.toString(),
              context?.exception == nil, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MarkdownDocument.self, from: data)
    }
}
