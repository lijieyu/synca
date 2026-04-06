import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
import Darwin

enum DeviceInfo {
    static var displayModelName: String {
        #if os(iOS)
        let identifier = simulatorModelIdentifier() ?? hardwareIdentifier()
        return iosModelMap[identifier] ?? fallbackiOSName(for: identifier)
        #elseif os(macOS)
        return macDisplayName
        #else
        return "Unknown Device"
        #endif
    }

    static var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        return "iOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #elseif os(macOS)
        return "macOS \(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #else
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        #endif
    }

    static var appVersionString: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(version) (\(build))"
    }

    private static func hardwareIdentifier() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
    }

    #if os(iOS)
    private static func simulatorModelIdentifier() -> String? {
        let identifier = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let identifier, !identifier.isEmpty else { return nil }
        return identifier
    }

    private static func fallbackiOSName(for identifier: String) -> String {
        if identifier == "i386" || identifier == "x86_64" || identifier == "arm64" {
            return "iPhone Simulator"
        }
        if identifier.hasPrefix("iPhone") {
            return "iPhone"
        }
        if identifier.hasPrefix("iPad") {
            return "iPad"
        }
        if identifier.hasPrefix("iPod") {
            return "iPod touch"
        }
        return "Apple Device"
    }

    private static let iosModelMap: [String: String] = [
        "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max",
        "iPhone14,4": "iPhone 13 mini",
        "iPhone14,5": "iPhone 13",
        "iPhone14,6": "iPhone SE (3rd generation)",
        "iPhone14,7": "iPhone 14",
        "iPhone14,8": "iPhone 14 Plus",
        "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15",
        "iPhone15,5": "iPhone 15 Plus",
        "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max",
        "iPhone17,3": "iPhone 16",
        "iPhone17,4": "iPhone 16 Plus",
        "iPhone17,5": "iPhone 16e",
        "iPad14,8": "iPad Air 11-inch (M2)",
        "iPad14,9": "iPad Air 13-inch (M2)",
        "iPad16,3": "iPad Pro 11-inch (M4)",
        "iPad16,4": "iPad Pro 13-inch (M4)",
        "iPad16,5": "iPad Pro 11-inch (M4)",
        "iPad16,6": "iPad Pro 13-inch (M4)",
        "iPad16,7": "iPad mini (A17 Pro)",
        "iPad15,3": "iPad Air 11-inch (M3)",
        "iPad15,4": "iPad Air 13-inch (M3)",
    ]
    #endif

    #if os(macOS)
    private static let macDisplayName: String = {
        if let machineName = systemProfilerMachineName() {
            return machineName
        }

        let identifier = hardwareModelIdentifier()
        return macModelMap[identifier] ?? identifier
    }()

    private static func hardwareModelIdentifier() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let bytes = model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func systemProfilerMachineName() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPHardwareDataType", "-json"]

        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = Pipe()

        do {
            try task.run()
        } catch {
            return nil
        }

        task.waitUntilExit()
        guard task.terminationStatus == 0 else { return nil }

        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let hardware = jsonObject["SPHardwareDataType"] as? [[String: Any]],
            let machineName = hardware.first?["machine_name"] as? String,
            !machineName.isEmpty
        else {
            return nil
        }

        return machineName
    }

    private static let macModelMap: [String: String] = [
        "Mac16,8": "MacBook Pro",
    ]
    #endif
}
