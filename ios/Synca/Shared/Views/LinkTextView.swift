import SwiftUI

#if os(iOS)
import UIKit

struct LinkTextView: UIViewRepresentable {
    let attributedText: NSAttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.adjustsFontForContentSizeCategory = true
        textView.dataDetectorTypes = []
        textView.delegate = context.coordinator
        textView.linkTextAttributes = [
            .foregroundColor: UIColor.link,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.attributedText != attributedText {
            uiView.attributedText = attributedText
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let targetWidth = proposal.width ?? uiView.bounds.width
        guard targetWidth > 0 else { return nil }
        let fittingSize = uiView.sizeThatFits(CGSize(width: targetWidth, height: .greatestFiniteMagnitude))
        return CGSize(width: targetWidth, height: ceil(fittingSize.height))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        func textView(
            _ textView: UITextView,
            shouldInteractWith url: URL,
            in characterRange: NSRange,
            interaction: UITextItemInteraction
        ) -> Bool {
            UIApplication.shared.open(url)
            return false
        }
    }
}

#elseif os(macOS)
import AppKit

// Dummy view for macOS to maintain cross-platform compilation
// macOS uses MacSelectableText directly in MessageBubbleView
struct LinkTextView: View {
    let attributedText: NSAttributedString
    var body: some View { EmptyView() }
}
#else
// Fallback for other platforms
struct LinkTextView: View {
    let attributedText: NSAttributedString
    var body: some View { EmptyView() }
}
#endif
