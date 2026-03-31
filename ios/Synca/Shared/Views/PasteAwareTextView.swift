import SwiftUI

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

struct PasteAwareTextView: UIViewRepresentable {
    @Binding var text: String
    let onImagePaste: (Data) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = PasteAwareUITextView()
        textView.delegate = context.coordinator
        textView.onImagePaste = onImagePaste
        textView.backgroundColor = UIColor.systemGray6
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.layer.cornerRadius = 20
        textView.clipsToBounds = true
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = false
        textView.returnKeyType = .default
        textView.text = text
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text = textView.text
        }
    }
}

final class PasteAwareUITextView: UITextView {
    var onImagePaste: ((Data) -> Void)?

    override func paste(_ sender: Any?) {
        if let imageData = pastedImageData() {
            onImagePaste?(imageData)
            return
        }

        super.paste(sender)
    }

    private func pastedImageData() -> Data? {
        let pasteboard = UIPasteboard.general

        if let pngData = pasteboard.data(forPasteboardType: UTType.png.identifier) {
            return pngData
        }

        if let jpegData = pasteboard.data(forPasteboardType: UTType.jpeg.identifier) {
            return jpegData
        }

        if let heicData = pasteboard.data(forPasteboardType: UTType.heic.identifier) {
            return heicData
        }

        if let image = pasteboard.image {
            return image.pngData()
        }

        return nil
    }
}
#endif
