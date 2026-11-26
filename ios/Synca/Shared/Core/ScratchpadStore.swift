import Foundation
import SwiftUI

@MainActor
final class ScratchpadStore: ObservableObject {
    private static var stores: [String: ScratchpadStore] = [:]
    static func shared(account: String) -> ScratchpadStore {
        if let existing = stores[account] { return existing }
        let store = ScratchpadStore(account: account)
        stores[account] = store
        return store
    }
    @Published private(set) var draft = ScratchDraft()
    @Published var status = "scratch.local"
    @Published var error: String?
    @Published var remote: ScratchDocument?
    @Published var copies: [ScratchCopy] = []
    @Published var images: [SyncaMessage] = []
    @Published var uploading = false
    private let account: String
    private let file: URL
    private var imageFile: URL { file.appendingPathExtension("images") }
    private var localSaveFailed = false
    private var busy = false
    private var debounce: Task<Void, Never>?
    private var sameAccount: Bool { APIClient.shared.currentUserId == account }

    init(account: String) {
        self.account = account
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Scratchpads", isDirectory: true)
        file = directory.appendingPathComponent(Data(account.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_") + ".json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { draft = try JSONDecoder().decode(ScratchDraft.self, from: Data(contentsOf: file)) }
            if let data = try? Data(contentsOf: imageFile), let cached = try? JSONDecoder().decode([SyncaMessage].self, from: data) { images = cached }
        } catch { localSaveFailed = true; self.error = String(syncaLocalized: "scratch.local_error") }
    }
    private func persist() {
        do { try JSONEncoder().encode(draft).write(to: file, options: .atomic); localSaveFailed = false }
        catch { localSaveFailed = true; self.error = String(syncaLocalized: "scratch.local_error") }
    }
    func edit(_ text: String) {
        guard sameAccount else { return }
        draft.content = text; draft.dirty = true; persist(); status = localSaveFailed ? "scratch.local_error" : "scratch.local"
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(700)) } catch { return }
            await self?.sync()
        }
    }
    func sync() async {
        guard sameAccount, !busy, remote == nil else { return }
        busy = true; defer { busy = false }
        let sent = draft
        do {
            if sent.dirty {
                status = "scratch.saving"
                let document = try await APIClient.shared.saveScratchpad(sent, account: account)
                guard sameAccount else { return }
                draft.accept(sent: sent.content, remote: document)
            } else {
                let document = try await APIClient.shared.getScratchpad(account: account)
                guard sameAccount else { return }
                let changed = draft.revision != document.revision
                draft.receive(document)
                if changed { await loadExtras() }
            }
            persist(); status = draft.dirty ? (localSaveFailed ? "scratch.local_error" : "scratch.local") : "scratch.saved"; if !localSaveFailed { error = nil }
        } catch let conflict as ScratchConflict {
            guard sameAccount else { return }
            remote = conflict.current; status = "scratch.conflict"
            await loadExtras()
        } catch {
            guard sameAccount else { return }
            status = localSaveFailed ? "scratch.local_error" : "scratch.local"; self.error = String(syncaLocalized: localSaveFailed ? "scratch.local_error" : "scratch.offline")
        }
    }
    func loadExtras() async {
        do {
            async let c = APIClient.shared.getScratchCopies(account: account)
            async let i = APIClient.shared.getScratchImages(account: account)
            let (newCopies,newImages) = try await (c,i)
            guard sameAccount else { return }
            copies = newCopies.conflicts; images = newImages.images
            try JSONEncoder().encode(images).write(to: imageFile, options: .atomic)
        } catch { if sameAccount { self.error = String(syncaLocalized: "scratch.offline") } }
    }
    func resolve(useLocal: Bool) async {
        guard let remote, sameAccount, !busy else { return }
        if useLocal {
            draft.revision = remote.revision; draft.dirty = true; draft.preserveCurrent = true
            self.remote = nil; persist(); await sync(); await loadExtras(); return
        }
        busy = true
        let local = draft.content
        do {
            let cloud = try await APIClient.shared.preserveScratchCopy(local, account: account)
            guard sameAccount else { busy = false; return }
            guard draft.content == local else { error = String(syncaLocalized: "scratch.finish_current"); busy = false; return }
            draft = ScratchDraft(content: cloud.content, revision: cloud.revision)
            self.remote = nil; persist(); status = "scratch.saved"; busy = false
            await loadExtras()
        } catch { busy = false; self.error = String(syncaLocalized: "scratch.offline") }
    }
    func upload(_ data: Data) async {
        guard sameAccount, !uploading else { return }
        uploading = true; defer { uploading = false }
        do {
            let image = try await APIClient.shared.sendImageMessage(imageData: data, scratchpad: true, scratchpadAccount: account)
            guard sameAccount else { return }
            images.append(image)
            try JSONEncoder().encode(images).write(to: imageFile, options: .atomic)
            edit(draft.content + "\n![](synca-image:\(image.id))\n")
        } catch { if sameAccount { self.error = String(syncaLocalized: "scratch.upload_error") } }
    }
    func restore(_ copy: ScratchCopy) -> Bool {
        guard !draft.dirty, remote == nil else { error = String(syncaLocalized: "scratch.finish_current"); return false }
        draft.preserveCurrent = true
        edit(copy.content)
        return true
    }
    func deleteCopy(_ id: String) async {
        do { try await APIClient.shared.deleteScratchCopy(id, account: account); await loadExtras() }
        catch { self.error = String(syncaLocalized: "scratch.offline") }
    }
    func deleteImage(_ id: String) async {
        guard !draft.dirty else { error = String(syncaLocalized: "scratch.finish_current"); return }
        do { try await APIClient.shared.deleteScratchImage(id, account: account); await loadExtras() }
        catch { self.error = String(syncaLocalized: "scratch.image_in_use") }
    }
}
