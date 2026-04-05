import SwiftUI

#if os(iOS)
import UIKit
import UniformTypeIdentifiers

struct PasteAwareTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let onImagePaste: (Data) -> Void
    let onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, height: $height, onImagePaste: onImagePaste, onSubmit: onSubmit)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = PasteAwareUITextView()
        textView.delegate = context.coordinator
        textView.onImagePaste = onImagePaste
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false // Important for self-sizing
        textView.isEditable = true
        textView.isSelectable = true
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
        let onSubmit: () -> Void

        init(text: Binding<String>, height: Binding<CGFloat>, onImagePaste: @escaping (Data) -> Void, onSubmit: @escaping () -> Void) {
            _text = text
            _height = height
            self.onImagePaste = onImagePaste
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

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            let pb = UIPasteboard.general
            return pb.hasStrings || pb.hasImages || pb.hasColors || pb.numberOfItems > 0
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        if let imageData = pastedImageData() {
            onImagePaste?(imageData)
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
}
#endif
