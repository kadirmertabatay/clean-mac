// Builds the animated tour shown at the top of the README (docs/images/demo.gif) from the screenshots.
//
//   ./scripts/screenshots.sh              # regenerate the screenshots first if the UI changed
//   swift scripts/make-demo-gif.swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let images = root.appendingPathComponent("docs/images")

/// Screens in tour order, with how long each stays on screen (seconds).
let tour: [(name: String, seconds: Double)] = [
    ("splash", 1.6), ("assistant", 2.6), ("smart-cleanup", 2.6), ("treemap", 2.2),
    ("duplicates", 2.2), ("junk", 2.2), ("growth", 2.2), ("similar-photos", 2.0),
]
let width: CGFloat = 880          // README column width on GitHub
let fadeFrames = 3                // short cross-fade between screens
let fadeSeconds = 0.06

func load(_ name: String) -> CGImage {
    let url = images.appendingPathComponent("\(name).png")
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Missing \(url.path)") }
    return image
}

let first = load(tour[0].name)
let height = (width * CGFloat(first.height) / CGFloat(first.width)).rounded()

/// Draws `a` blended into `b` (t = 0 → a, t = 1 → b) on a canvas of the GIF size.
func frame(_ a: CGImage, _ b: CGImage? = nil, t: CGFloat = 0) -> CGImage {
    let context = CGContext(data: nil, width: Int(width), height: Int(height), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.draw(a, in: rect)
    if let b {
        context.setAlpha(t)
        context.draw(b, in: rect)
    }
    return context.makeImage()!
}

let output = images.appendingPathComponent("demo.gif")
let frameCount = tour.count * (1 + fadeFrames)
guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else {
    fatalError("Can't create \(output.path)")
}
CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)

func add(_ image: CGImage, seconds: Double) {
    let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: seconds,
                                                      kCGImagePropertyGIFUnclampedDelayTime: seconds]]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
}

let screens = tour.map { load($0.name) }
for (i, step) in tour.enumerated() {
    add(frame(screens[i]), seconds: step.seconds)
    let next = screens[(i + 1) % screens.count]
    for f in 1...fadeFrames {
        add(frame(screens[i], next, t: CGFloat(f) / CGFloat(fadeFrames + 1)), seconds: fadeSeconds)
    }
}
guard CGImageDestinationFinalize(destination) else { fatalError("Couldn't write \(output.path)") }
let size = (try? FileManager.default.attributesOfItem(atPath: output.path)[.size] as? Int) ?? 0
print("Wrote \(output.path) (\(Int(width))×\(Int(height)), \(size / 1024) KB)")
