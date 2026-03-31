import SwiftUI
import CoreTransferable

struct ImagePayload: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            return ImagePayload(data: data)
        }
    }
}

struct TestView: View {
    @State private var text = ""
    var body: some View {
        TextField("Test", text: $text)
            .pasteDestination(for: ImagePayload.self) { items in
                print("pasted")
            }
    }
}
