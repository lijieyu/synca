import SwiftUI

extension Color {
    /// Synca's primary brand color: Comet Purple
    static let syncaPurple = Color(red: 0.490, green: 0.302, blue: 1.000)
    
    /// Synca's secondary accent color: Mint Green (for processed items)
    static let syncaMint = Color.green.opacity(0.8)
    
    /// Light version of mint green for backgrounds
    static let syncaMintLight = Color.green.opacity(0.06)
}
