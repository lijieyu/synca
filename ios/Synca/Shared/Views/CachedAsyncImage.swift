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
    @State private var loadedRequestID: String?

    init(url: URL, maximumPixelSize: Int = 1024, onSuccess: (() -> Void)? = nil, @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.maximumPixelSize = maximumPixelSize
        self.onSuccess = onSuccess
        self.content = content
    }

    var body: some View {
        let requestID = "\(url.absoluteString)-\(maximumPixelSize)-\(reloadID)"
        content(phase)
            .task(id: requestID) {
                await loadImage(requestID: requestID)
            }
    }

    @MainActor
    private func loadImage(requestID: String) async {
        // Lazy rows restart their task when they re-enter the viewport. Retain
        // successful content instead of briefly shrinking back to the placeholder.
        if loadedRequestID == requestID, case .success = phase { return }
        loadedRequestID = nil
        phase = .empty
        
        do {
            let image = try await ImageCache.thumbnail(
                for: url,
                authorizationToken: APIClient.shared.token,
                maximumPixelSize: maximumPixelSize
            )
            try Task.checkCancellation()
            loadedRequestID = requestID
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
