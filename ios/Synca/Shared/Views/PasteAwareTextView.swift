import SwiftUI

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

struct PasteAwareTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let isSending: Bool
    let onImagePaste: (Data) -> Void
    let onFilePaste: (PendingFileUpload) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, onImagePaste: onImagePaste, onFilePaste: onFilePaste, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = PasteAwareUITextView()
        textView.delegate = context.coordinator
        textView.onImagePaste = onImagePaste
        textView.onFilePaste = onFilePaste
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false // Important for self-sizing
        textView.isEditable = !isSending
        textView.isSelectable = !isSending
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.returnKeyType = .send
        textView.enablesReturnKeyAutomatically = true
        if let tint = UIColor(named: "AccentColor") {
            textView.tintColor = tint
        }
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        uiView.isEditable = !isSending
        uiView.isSelectable = !isSending
        if let textView = uiView as? PasteAwareUITextView {
            textView.onImagePaste = onImagePaste
            textView.onFilePaste = onFilePaste
        }
        
        // Force height update
        DispatchQueue.main.async {
            self.updateHeight(uiView)
        }
    }

    private func updateHeight(_ textView: UITextView) {
        let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
        if height != size.height {
            height = size.height
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        @Binding var height: CGFloat
        let onImagePaste: (Data) -> Void
        let onFilePaste: (PendingFileUpload) -> Void
        let onSubmit: () -> Void

        init(text: Binding<String>, height: Binding<CGFloat>, onImagePaste: @escaping (Data) -> Void, onFilePaste: @escaping (PendingFileUpload) -> Void, onSubmit: @escaping () -> Void) {
            _text = text
            _height = height
            self.onImagePaste = onImagePaste
            self.onFilePaste = onFilePaste
            self.onSubmit = onSubmit
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
            let size = textView.sizeThatFits(CGSize(width: textView.frame.width, height: CGFloat.greatestFiniteMagnitude))
            if height != size.height {
                height = size.height
            }
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            if text == "\n" {
                onSubmit()
                return false
            }
            return true
        }
    }
}

final class PasteAwareUITextView: UITextView {
    var onImagePaste: ((Data) -> Void)?
    var onFilePaste: ((PendingFileUpload) -> Void)?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            let pb = UIPasteboard.general
            return pb.hasStrings || pb.hasImages || pb.hasColors || pb.numberOfItems > 0
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if UIPasteboard.general.hasStrings {
            super.paste(sender)
            return
        }

        if let imageData = pastedImageData() {
            onImagePaste?(imageData)
            return
        }

        if let provider = pastedFileProvider() {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let fileURL = item as? URL {
                    url = fileURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }

                guard let url, let pendingFile = PendingFileUpload.read(from: url) else { return }
                DispatchQueue.main.async {
                    self?.onFilePaste?(pendingFile)
                }
            }
            return
        }
        super.paste(sender)
    }

    private func pastedImageData() -> Data? {
        let pasteboard = UIPasteboard.general
        
        let types = [UTType.png, UTType.jpeg, UTType.heic]
        for type in types {
            if let data = pasteboard.data(forPasteboardType: type.identifier) {
                return data
            }
        }
        
        if let image = pasteboard.image {
            return image.pngData()
        }
        return nil
    }

    private func pastedFileProvider() -> NSItemProvider? {
        let providers = UIPasteboard.general.itemProviders

        for provider in providers {
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else {
                continue
            }
            return provider
        }
        return nil
    }
}
#endif
