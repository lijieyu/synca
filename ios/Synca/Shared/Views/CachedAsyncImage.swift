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
    let maximumPixelSize: Int
    let onSuccess: (() -> Void)?
    @ViewBuilder let content: (AsyncImagePhase) -> Content
    
    @State private var phase: AsyncImagePhase = .empty
    @State private var reloadID = UUID()

    init(url: URL, maximumPixelSize: Int = 1024, onSuccess: (() -> Void)? = nil, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.maximumPixelSize = maximumPixelSize
        self.onSuccess = onSuccess
        self.content = content
    }

    var body: some View {
        content(phase)
            .task(id: "\(url.absoluteString)-\(reloadID)") {
                await loadImage()
            }
    }

    @MainActor
    private func loadImage() async {
        phase = .empty
        
        do {
            let image = try await ImageCache.thumbnail(
                for: url,
                authorizationToken: APIClient.shared.token,
                maximumPixelSize: maximumPixelSize
            )
            try Task.checkCancellation()
            phase = .success(Image(decorative: image, scale: 1, orientation: .up))
            onSuccess?()
        } catch {
            if !Task.isCancelled {
                phase = .failure(error)
            }
        }
    }
    
    /// Trigger a force reload by bypassing memory (but still potentially hitting disk)
    func retry() {
        reloadID = UUID()
    }
}
