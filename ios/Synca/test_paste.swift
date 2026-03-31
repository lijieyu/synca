import SwiftUI
import UniformTypeIdentifiers

struct ImagePayload: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            return ImagePayload(data: data)
        }
    }
}
