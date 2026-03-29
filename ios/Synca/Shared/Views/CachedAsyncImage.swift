import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// A replacement for AsyncImage that persists data to a disk cache (Library/Caches).
/// Images are downloaded once and subsequent loads are instant from disk.
struct CachedAsyncImage<Content: View>: View {
    let url: URL
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    
    @State private var phase: AsyncImagePhase = .empty
    @State private var loadTask: Task<Void, Never>?
    @State private var reloadID = UUID()

    var body: some View {
        content(phase)
            .id(reloadID)
            .onAppear {
                loadImage()
            }
            .onChange(of: url) { _ in
                loadImage()
            }
            .onDisappear {
                loadTask?.cancel()
            }
    }

    private func loadImage() {
        loadTask?.cancel()
        
        // Initial state
        if let data = ImageCache.getCachedData(for: url) {
            #if os(iOS)
            if let uiImage = UIImage(data: data) {
                phase = .success(Image(uiImage: uiImage))
                return
            }
            #elseif os(macOS)
            if let nsImage = NSImage(data: data) {
                phase = .success(Image(nsImage: nsImage))
                return
            }
            #endif
        }
        
        phase = .empty
        
        loadTask = Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    phase = .failure(URLError(.badServerResponse))
                    return
                }
                
                // Save to disk cache
                ImageCache.saveCachedData(data, for: url)
                
                #if os(iOS)
                if let uiImage = UIImage(data: data) {
                    phase = .success(Image(uiImage: uiImage))
                } else {
                    phase = .failure(URLError(.cannotDecodeContentData))
                }
                #elseif os(macOS)
                if let nsImage = NSImage(data: data) {
                    phase = .success(Image(nsImage: nsImage))
                } else {
                    phase = .failure(URLError(.cannotDecodeContentData))
                }
                #endif
            } catch {
                if !Task.isCancelled {
                    phase = .failure(error)
                }
            }
        }
    }
    
    /// Trigger a force reload by bypassing memory (but still potentially hitting disk)
    func retry() {
        reloadID = UUID()
        loadImage()
    }
}
