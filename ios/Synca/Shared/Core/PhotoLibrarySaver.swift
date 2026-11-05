#if os(iOS)
import Photos
import UIKit

/// Photos invokes change blocks on its own queue. Construct them outside MainActor isolation.
enum PhotoLibrarySaver {
    nonisolated static func saveImage(at url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw SaveError.permissionDenied }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
        }
    }

    enum SaveError: LocalizedError {
        case permissionDenied
        nonisolated var errorDescription: String? {
            String(localized: "photo_save.permission_denied", bundle: .main)
        }
    }

    @MainActor static func announce(success: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        UIAccessibility.post(notification: .announcement, argument: String(localized: success ? "image_preview.save_success" : "image_preview.save_failed", bundle: .main))
    }
}
#endif
