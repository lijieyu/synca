import SwiftUI
import PhotosUI

struct ScratchpadView: View {
    @StateObject private var store: ScratchpadStore
    @State private var preview = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCopies = false
    @State private var showImages = false
    @State private var deleteCopy: String?
    @State private var deleteImage: String?
    @Environment(\.scenePhase) private var scenePhase
    init(account: String) { _store = StateObject(wrappedValue: ScratchpadStore.shared(account: account)) }
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack { controls; Spacer(); status }
                VStack(alignment: .leading) { controls; status }
            }.padding(.horizontal, 16).padding(.vertical, 10)
            Divider()
            if store.remote != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("scratch.conflict_detail").font(.callout)
                    HStack {
                        Button("scratch.use_cloud") { Task { await store.resolve(useLocal: false) } }
                        Button("scratch.use_local") { Task { await store.resolve(useLocal: true) } }
                    }
                }.padding().background(.regularMaterial)
            }
            if let error = store.error { Text(error).font(.footnote).foregroundStyle(.secondary).padding(12).accessibilityAddTraits(.updatesFrequently) }
            if preview {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(ScratchBlock.parse(store.draft.content)) { block in
                            if let id = block.imageID { image(id) }
                            else {
                                ForEach(ScratchParagraph.parse(block.text)) { paragraph in
                                    paragraphView(paragraph).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }.padding(16)
                }
            } else {
                TextEditor(text: Binding(get: { store.draft.content }, set: { store.edit(String($0.prefix(250000))) }))
                    .font(.body).padding(.horizontal, 12).padding(.vertical, 8)
                    .accessibilityLabel(Text("scratch.editor")).accessibilityIdentifier("scratch-editor")
            }
        }
        .task {
            await store.sync(); await store.loadExtras()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { break }
                if scenePhase == .active { await store.sync() }
            }
        }
        .onChange(of: scenePhase) { phase in if phase == .active { Task { await store.sync(); await store.loadExtras() } } }
        .onChange(of: selectedPhoto) { photo in
            guard let photo else { return }
            Task {
                if let data = try? await photo.loadTransferable(type: Data.self) { await store.upload(data) }
                else { store.error = String(syncaLocalized: "scratch.upload_error") }
                selectedPhoto = nil
            }
        }
        .sheet(isPresented: $showCopies) { copiesSheet }
        .sheet(isPresented: $showImages) { imagesSheet }
    }
    private var status: some View { Text(LocalizedStringKey(store.status)).font(.caption).foregroundStyle(.secondary).accessibilityIdentifier("scratch-save-status") }
    private var controls: some View {
        HStack(spacing: 12) {
            Picker("scratch.edit", selection: $preview) {
                Text("scratch.edit").tag(false); Text("scratch.preview").tag(true)
            }.pickerStyle(.segmented).frame(maxWidth: 230)
            PhotosPicker(selection: $selectedPhoto, matching: .images) { Image(systemName: "photo.badge.plus").frame(minWidth: 44, minHeight: 44) }
                .disabled(store.uploading).accessibilityLabel(Text(store.uploading ? "scratch.uploading" : "scratch.image"))
            Menu {
                Button("scratch.copies", systemImage: "clock.arrow.circlepath") { showCopies = true; Task { await store.loadExtras() } }
                Button("scratch.images", systemImage: "photo.on.rectangle") { showImages = true; Task { await store.loadExtras() } }
            } label: { Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44) }.accessibilityLabel(Text("scratch.copies"))
        }
    }
    @ViewBuilder private func image(_ id: String) -> some View {
        if let asset = store.images.first(where: { $0.id == id }), let value = asset.imageUrl, let url = URL(string: value) {
            CachedAsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit().frame(maxHeight: 480) }
                else { Image(systemName: "photo").foregroundStyle(.secondary).frame(height: 64) }
            }.accessibilityLabel(Text("scratch.image"))
        } else { Image(systemName: "photo").foregroundStyle(.secondary).accessibilityLabel(Text("scratch.image")) }
    }
    @ViewBuilder private func paragraphView(_ paragraph: ScratchParagraph) -> some View {
        switch paragraph.kind {
        case .heading(let level):
            Text((try? AttributedString(markdown: paragraph.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(paragraph.text)).font(level == 1 ? .title : level == 2 ? .title2 : .headline)
                .fontWeight(.semibold).accessibilityAddTraits(.isHeader)
        case .code:
            ScrollView(.horizontal) { Text(paragraph.text).font(.system(.body, design: .monospaced)).padding(12) }
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        case .quote:
            HStack(alignment: .top, spacing: 12) { Rectangle().fill(.secondary).frame(width: 3); markdown(paragraph.text).foregroundStyle(.secondary) }
                .fixedSize(horizontal: false, vertical: true)
        case .body: markdown(paragraph.text)
        }
    }
    private func markdown(_ text: String) -> Text {
        #if os(iOS)
        Text(AttributedString(MessageMarkdownRenderer.render(text, baseColor: .label)))
        #else
        Text(AttributedString(MessageMarkdownRenderer.render(text, baseColor: .labelColor)))
        #endif
    }
    private var copiesSheet: some View {
        NavigationStack {
            List {
                if store.copies.isEmpty { Text("scratch.no_copies").foregroundStyle(.secondary) }
                ForEach(store.copies) { copy in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(copy.createdAt).font(.caption).foregroundStyle(.secondary)
                        Text(copy.content).lineLimit(8)
                        HStack {
                            Button("scratch.restore") { if store.restore(copy) { showCopies = false } }
                            Spacer()
                            Button("common.delete", role: .destructive) { deleteCopy = copy.id }
                        }.buttonStyle(.borderless)
                    }.padding(.vertical, 8)
                }
            }.navigationTitle(Text("scratch.copies"))
             .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { showCopies = false } } }
             .confirmationDialog(Text("scratch.delete_copy"), isPresented: Binding(get: { deleteCopy != nil }, set: { if !$0 { deleteCopy = nil } })) {
                 Button("common.delete", role: .destructive) { if let id = deleteCopy { Task { await store.deleteCopy(id) } }; deleteCopy = nil }
             }
        }.frame(minWidth: 300, minHeight: 400)
    }
    private var imagesSheet: some View {
        NavigationStack {
            List(store.images) { asset in
                VStack(alignment: .leading) {
                    image(asset.id).frame(maxHeight: 140)
                    HStack {
                        Button("scratch.insert") { store.edit(store.draft.content + "\n![](synca-image:\(asset.id))\n"); showImages = false }
                        Spacer()
                        Button("common.delete", role: .destructive) { deleteImage = asset.id }.disabled(store.draft.dirty)
                    }.buttonStyle(.borderless)
                }
            }.navigationTitle(Text("scratch.images"))
             .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.done") { showImages = false } } }
             .confirmationDialog(Text("scratch.delete_image"), isPresented: Binding(get: { deleteImage != nil }, set: { if !$0 { deleteImage = nil } })) {
                 Button("common.delete", role: .destructive) { if let id = deleteImage { Task { await store.deleteImage(id) } }; deleteImage = nil }
             }
        }.frame(minWidth: 300, minHeight: 400)
    }
}
