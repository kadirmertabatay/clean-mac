// Generates the GitHub social preview image (1280×640) shown when the repository is shared.
//
//   swift scripts/make-social-preview.swift
//
// Inputs: Resources/AppIcon-1024.png and docs/images/assistant.png. Output: docs/images/social-preview.png.
// Upload it under GitHub › Settings › General › Social preview.
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
func image(_ path: String) -> NSImage {
    guard let image = NSImage(contentsOf: root.appendingPathComponent(path)) else { fatalError("Missing \(path)") }
    return image
}
let icon = image("Resources/AppIcon-1024.png")
let screenshot = image("docs/images/assistant.png")

let size = NSSize(width: 1280, height: 640)
let scale: CGFloat = 1   // GitHub requires the image to be under 1 MB
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

// Background: deep navy gradient with a soft blue glow behind the icon.
NSGradient(colors: [NSColor(srgbRed: 0.05, green: 0.08, blue: 0.16, alpha: 1),
                    NSColor(srgbRed: 0.08, green: 0.14, blue: 0.28, alpha: 1)])!
    .draw(in: NSRect(origin: .zero, size: size), angle: -30)
NSGradient(colors: [NSColor(srgbRed: 0.2, green: 0.55, blue: 1, alpha: 0.35), .clear])!
    .draw(fromCenter: NSPoint(x: 230, y: 400), radius: 0, toCenter: NSPoint(x: 230, y: 400), radius: 380, options: [])

// Screenshot on the right, tilted out of the frame like a product shot.
NSGraphicsContext.saveGraphicsState()
let transform = NSAffineTransform()
transform.translateX(by: 690, yBy: 70)
transform.rotate(byDegrees: 0)
transform.concat()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.55)
shadow.shadowBlurRadius = 40
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
let shotHeight: CGFloat = 520
let shotWidth = shotHeight * screenshot.size.width / screenshot.size.height
screenshot.draw(in: NSRect(x: 0, y: 0, width: shotWidth, height: shotHeight))
NSGraphicsContext.restoreGraphicsState()

// Icon and text on the left.
icon.draw(in: NSRect(x: 72, y: 330, width: 230, height: 230))

func draw(_ text: String, at point: NSPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        .draw(at: point)
}
let secondary = NSColor.white.withAlphaComponent(0.78)
draw("CleanMac", at: NSPoint(x: 88, y: 228), size: 64, weight: .bold, color: .white)
draw("A fully local storage assistant for macOS.", at: NSPoint(x: 92, y: 182), size: 25, weight: .regular, color: secondary)
draw("Find what fills your disk and clean it up safely.", at: NSPoint(x: 92, y: 148), size: 25, weight: .regular, color: secondary)
draw("Open source · MIT · SwiftUI · No network · English | Türkçe", at: NSPoint(x: 92, y: 90), size: 18, weight: .medium,
     color: NSColor(srgbRed: 0.55, green: 0.75, blue: 1, alpha: 1))

NSGraphicsContext.restoreGraphicsState()

let output = root.appendingPathComponent("docs/images/social-preview.png")
try! rep.representation(using: .png, properties: [:])!.write(to: output)
print("Wrote \(output.path)")
