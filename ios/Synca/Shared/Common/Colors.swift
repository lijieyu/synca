import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

extension Color {
    /// Synca's primary brand color: Comet Purple
    static let syncaPurple = Color(red: 0.490, green: 0.302, blue: 1.000)
    
    /// Synca's secondary accent color: Mint Green (for processed items)
    static let syncaMint = Color.green.opacity(0.8)
    
    /// Light version of mint green for backgrounds
    static let syncaMintLight = Color.green.opacity(0.06)

    #if os(iOS)
    /// App page background that keeps message cards visually elevated in both light and dark mode.
    static let syncaPageBackground = Color(uiColor: .systemGroupedBackground)
    /// Default card background for uncleared messages, matched to grouped list cells.
    static let syncaCardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let syncaCardBorder = Color.black.opacity(0.08)
    static let syncaInputFieldBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let syncaInputFieldBorder = Color.black.opacity(0.08)
    #elseif os(macOS)
    /// Slightly gray in light mode, near-black in dark mode, so cards stay visually elevated.
    static let syncaPageBackground = Color(
        nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.018, alpha: 1)
            } else {
                return NSColor(calibratedWhite: 0.972, alpha: 1)
            }
        }
    )
    /// White-ish card in light mode, noticeably lighter gray card in dark mode.
    static let syncaCardBackground = Color(
        nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.102, alpha: 1)
            } else {
                return NSColor(calibratedWhite: 0.992, alpha: 1)
            }
        }
    )
    static let syncaCardBorder = Color(
        nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 1.0, alpha: 0.12)
            } else {
                return NSColor(calibratedWhite: 0.0, alpha: 0.08)
            }
        }
    )
    static let syncaInputFieldBackground = Color(
        nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.096, alpha: 1)
            } else {
                return NSColor(calibratedWhite: 0.992, alpha: 1)
            }
        }
    )
    static let syncaInputFieldBorder = Color(
        nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 1.0, alpha: 0.13)
            } else {
                return NSColor(calibratedWhite: 0.0, alpha: 0.08)
            }
        }
    )
    #endif
}
