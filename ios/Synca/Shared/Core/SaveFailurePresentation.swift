import Foundation

enum SaveFailurePresentation {
    static func requiresFolderAuthorization(_ error: Error) -> Bool {
        let nsError = error as NSError

        if nsError.domain == NSCocoaErrorDomain {
            return nsError.code == NSFileWriteNoPermissionError
                || nsError.code == NSFileReadNoPermissionError
        }

        if nsError.domain == NSPOSIXErrorDomain {
            return nsError.code == Int(EACCES) || nsError.code == Int(EPERM)
        }

        return false
    }
}
