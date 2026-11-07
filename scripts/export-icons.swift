// Run from repository root: swift scripts/export-icons.swift
// Export the approved artwork; only sizing and platform corner masks are applied.
import AppKit
import ImageIO
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = NSImage(contentsOf: root.appendingPathComponent("assets/branding/synca-master.png"))!
func export(_ path: String, _ size: Int, inset: CGFloat = 0, rounded: Bool = false, opaque: Bool = false) throws {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: (opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast).rawValue)!
    context.interpolationQuality = .high
    let bounds = CGRect(x: 0, y: 0, width: size, height: size).insetBy(dx: CGFloat(size) * inset, dy: CGFloat(size) * inset)
    if rounded { context.addPath(CGPath(roundedRect: bounds, cornerWidth: bounds.width * 0.225, cornerHeight: bounds.height * 0.225, transform: nil)); context.clip() }
    var proposed = CGRect(origin: .zero, size: source.size)
    context.draw(source.cgImage(forProposedRect: &proposed, context: nil, hints: nil)!, in: bounds)
    let image = context.makeImage()!
    let destination = CGImageDestinationCreateWithURL(root.appendingPathComponent(path) as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    precondition(CGImageDestinationFinalize(destination))
}
let assets = "ios/Synca/Resources/Assets.xcassets/"
try export(assets + "AppIcon.appiconset/app-icon.png", 1024, opaque: true)
for size in [16,32,64,128,256,512,1024] {
    let name = size == 1024 ? "app-icon-mac.png" : "app-icon-mac-\(size).png"
    try export(assets + "AppIcon.appiconset/" + name, size, inset: 0.05, rounded: true)
}
try export(assets + "LoginLogo.imageset/login-logo.png", 512, rounded: true)
try export("web/public/logo.png", 512, rounded: true)
try export("web/public/favicon.png", 48, rounded: true)
try export("web/public/apple-touch-icon.png", 180, opaque: true)
try export("web/public/icon-192.png", 192, opaque: true)
try export("web/public/icon-512.png", 512, opaque: true)
print("Exported native, in-app, browser and home-screen icons.")
