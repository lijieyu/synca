"""Create an isolated native record/scratch renderer fixture. Never touches live data."""
from pathlib import Path
import json, shutil, subprocess, sys, struct, zlib
root = Path(__file__).resolve().parents[3]
dst = Path(sys.argv[1]).resolve()
if dst.exists(): raise SystemExit('Use a new temporary destination')
subprocess.run([sys.executable, str(root/'ios/Tests/ExperienceRegression/make-fixture.py'), str(dst)], check=True)
corpus = json.loads((root/'tests/fixtures/markdown-parity.json').read_text())
corpus.append(dict(id='large-tasks',source='- [ ] x\n'*31249+'- [ ] 尾部目标'))
source = next(f['source'] for f in corpus if f['id']=='showcase')
(dst/'Resources/markdown-fixture.json').write_text(json.dumps({f['id']: f['source'] for f in corpus},ensure_ascii=False))
# A deterministic local bitmap exercises rendering without network/image-service access.
def png_chunk(kind, data): return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
width,height=320,160
pixels=b''.join(b'\0'+b''.join(bytes((125,176,163) if (x//40+y//40)%2 else (218,233,220)) for x in range(width)) for y in range(height))
png=b'\x89PNG\r\n\x1a\n'+png_chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))+png_chunk(b'IDAT',zlib.compress(pixels))+png_chunk(b'IEND',b'')
(dst/'Resources/markdown-owned.png').write_bytes(png)
def edit(file, before, after):
 p=dst/file;s=p.read_text();assert before in s,(file,before);p.write_text(s.replace(before,after))
edit('Shared/Core/ScratchpadStore.swift','        self.account = account','        self.account = account')
edit('Shared/Core/ScratchpadStore.swift','    func sync() async {','    func sync() async { return;')
edit('Shared/Core/ScratchpadStore.swift','    func loadExtras() async {','    func loadExtras() async { return;')
edit('Shared/Core/ScratchpadStore.swift','    func loadPreviewImages() async {','    func loadPreviewImages() async { return;')
# Seed only the isolated account and isolated app-support directory.
image_record = dict(id='11111111-1111-4111-8111-111111111111',userId='visual-fixture',type='image',imageUrl='http://127.0.0.1:54671/markdown-owned.png',isCleared=False,isDeleted=False,sourceDevice='fixture',createdAt='2026-11-28T00:00:00Z',updatedAt='2026-11-28T00:00:00Z')
image_seed = 'images = try! JSONDecoder().decode([SyncaMessage].self, from: Data(#"'+json.dumps([image_record])+'"#.utf8)); '
edit('Shared/Core/ScratchpadStore.swift','    private func persist() {','    func seedMarkdownFixture(_ content: String) { '+image_seed+'draft.content = content; draft.dirty = false; status = "scratch.saved" }\n    private func persist() {')
edit('Shared/Core/ImageCacheManager.swift',
     '    static func thumbnail(for url: URL, authorizationToken: String?, maximumPixelSize: Int) async throws -> CGImage {',
     '    static func thumbnail(for url: URL, authorizationToken: String?, maximumPixelSize: Int) async throws -> CGImage {\n        if url.host == "127.0.0.1", url.lastPathComponent == "markdown-owned.png" { return try thumbnail(from: Data(contentsOf: Bundle.main.url(forResource: "markdown-owned", withExtension: "png")!), maximumPixelSize: maximumPixelSize) }')
edit('Shared/Core/ScratchpadStore.swift','appendingPathComponent("Scratchpads",','appendingPathComponent("MarkdownParityFixture",')
edit('Shared/Core/SyncManager.swift','    func updateMessageText(_ original: SyncaMessage, textContent: String) async throws {','    func updateMessageText(_ original: SyncaMessage, textContent: String) async throws {\n        if ProcessInfo.processInfo.arguments.contains("-qa-task-conflict") { throw APIError.textEditConflict }; if ProcessInfo.processInfo.arguments.contains("-qa-task-failure") { throw URLError(.notConnectedToInternet) }; try await Task.sleep(for: .milliseconds(150)); if let index = messages.firstIndex(where: { $0.id == original.id }) { messages[index].textContent = textContent }; return;')
edit('Shared/Views/ScratchpadView.swift','@State private var preview = false','@State private var preview = true')
(dst/'Shared/App/SyncaApp.swift').write_text(r'''import SwiftUI
@main struct SyncaApp: App {
    var body: some Scene { WindowGroup { MarkdownFixtureView() }
        #if os(macOS)
        .defaultSize(width: 1000, height: 820)
        #endif
    }
}
struct MarkdownFixtureView: View {
    @StateObject private var sync = SyncManager.shared
    @State private var scratch = false
    @State private var expanded = true
    @State private var dark = ProcessInfo.processInfo.arguments.contains("-qa-dark")
    @State private var editing = false
    private let source: String = {
        let corpus = try! JSONDecoder().decode([String: String].self, from: Data(contentsOf: Bundle.main.url(forResource: "markdown-fixture", withExtension: "json")!))
        let args = ProcessInfo.processInfo.arguments
        let key = args.firstIndex(of: "-qa-fixture").flatMap { index in index + 1 < args.count ? args[index + 1] : nil } ?? "showcase"
        let value = corpus[key] ?? corpus["showcase"]!
        if args.contains("-qa-encoded-images") { return value.replacingOccurrences(of: "synca-image:", with: "synca-image&#58;") }
        return args.contains("-qa-uppercase-images") ? value.replacingOccurrences(of: "synca-image:", with: "SYNCA-IMAGE:") : value
    }()
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("Preview", selection: $scratch) { Text("Record").tag(false); Text("Scratchpad").tag(true) }.pickerStyle(.segmented).frame(maxWidth: 300)
                Toggle("Dark", isOn: $dark).fixedSize()
                Button("Source") { editing = true }
            }.padding()
            Divider()
            if scratch { ScratchpadView(account: "visual-fixture") }
            else {
                ScrollView {
                    if let message = sync.messages.first {
                        MessageBubbleView(message: message, categories: [], onEdit: { editing = true }, onClear: {}, onDelete: {}, onCategoryChange: nil, onImageTap: {}, onImageLoaded: {}, textExpansion: $expanded)
                    }
                }
            }
        }.preferredColorScheme(dark ? .dark : .light)
        .overlay(alignment: .bottomLeading) { MarkdownFixtureAppearanceProbe() }
        .sheet(isPresented: $editing) { if let message = sync.messages.first { MessageTextEditorView(message: message) } }
        .overlay(alignment: .bottomTrailing) {
            // Read-only fixture instrumentation verifies exact source, never product UI.
            Text(sync.messages.first?.textContent == source ? "source-original" : "source-changed")
                .font(.system(size: 8)).accessibilityIdentifier("qa-source-state").allowsHitTesting(false)
        }
        .onAppear {
            if !sync.messages.isEmpty { sync.messages[0].textContent = source; sync.messages = [sync.messages[0]] }
            ScratchpadStore.shared(account: "visual-fixture").seedMarkdownFixture(source)
        }
    }
}
struct MarkdownFixtureAppearanceProbe: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Text(colorScheme == .dark ? "dark" : "light")
            .font(.system(size: 8)).accessibilityIdentifier("qa-rendered-scheme")
            .allowsHitTesting(false)
    }
}
''')
# Replace unrelated UI tests with isolated renderer checks.
shutil.rmtree(dst/'UITests'); (dst/'UITests').mkdir()
shutil.copy(Path(__file__).with_name('MarkdownParityTests.swift'),dst/'UITests/MarkdownParityTests.swift')
subprocess.run(['xcodegen','generate'],cwd=dst,check=True)
print(dst)
