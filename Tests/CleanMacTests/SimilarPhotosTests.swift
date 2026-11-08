import AppKit
import XCTest
@testable import CleanMac

final class SimilarPhotosTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("CleanMacPhotos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    /// Draws a photo-like scene: sky gradient, sun, mountains. `shift` simulates a burst shot.
    func scene(_ name: String, width: Int = 1200, shift: CGFloat = 0, hue: CGFloat = 0.58, quality: Double = 0.9, seed: Int = 0) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: width * 3 / 4, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let w = CGFloat(width), h = w * 3 / 4
        NSGradient(colors: [NSColor(hue: hue, saturation: 0.6, brightness: 0.95, alpha: 1),
                            NSColor(hue: hue + 0.05, saturation: 0.3, brightness: 0.7, alpha: 1)])!
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: -90)
        NSColor.systemYellow.setFill()
        NSBezierPath(ovalIn: NSRect(x: w * 0.7 + shift, y: h * 0.65, width: w * 0.12, height: w * 0.12)).fill()
        for k in 0..<5 {
            let x = w * CGFloat(k) / 4 - w * 0.15 + shift + CGFloat(seed * 37 % 200)
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: 0)); p.line(to: NSPoint(x: x + w * 0.2, y: h * (0.35 + 0.08 * CGFloat((k + seed) % 3)))); p.line(to: NSPoint(x: x + w * 0.4, y: 0))
            NSColor(hue: 0.33 - CGFloat(seed) * 0.05, saturation: 0.5, brightness: 0.3 + 0.08 * CGFloat(k), alpha: 1).setFill()
            p.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let url = dir.appendingPathComponent(name)
        try rep.representation(using: .jpeg, properties: [.compressionFactor: quality])!.write(to: url)
        return url
    }

    func entry(_ url: URL) -> FileEntry {
        let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        return FileEntry(url: url, size: size, modified: Date(), accessed: nil, isProtected: false)
    }

    func circles(_ name: String) throws -> URL {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 900, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 900).fill()
        for i in 0..<12 { for j in 0..<9 {
            NSColor(hue: CGFloat(i * j % 7) / 7, saturation: 0.8, brightness: 0.8, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: i * 100 + 10, y: j * 100 + 10, width: 80, height: 80)).fill()
        } }
        NSGraphicsContext.restoreGraphicsState()
        let url = dir.appendingPathComponent(name)
        try rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: url)
        return url
    }

    func testDistancesSeparateSimilarFromDifferent() throws {
        let original = try scene("orijinal.jpg")
        let resaved = try scene("copy-small.jpg", width: 800)
        let burst = try scene("seri-2.jpg", shift: 12)
        let different = try scene("baska.jpg", hue: 0.05, seed: 3)
        let unrelated = try circles("ilgisiz.jpg")

        let fp = [original, resaved, burst, different, unrelated].map { try! XCTUnwrap(SimilarPhotos.featurePrint($0)) }
        let dResaved = SimilarPhotos.distance(fp[0], fp[1])!
        let dBurst = SimilarPhotos.distance(fp[0], fp[2])!
        let dDifferent = SimilarPhotos.distance(fp[0], fp[3])!
        print("[photos] re-saved: \(dResaved), burst: \(dBurst), different: \(dDifferent)")
        XCTAssertLessThan(dResaved, SimilarPhotos.threshold)
        XCTAssertLessThan(dBurst, SimilarPhotos.threshold)
        XCTAssertGreaterThan(dDifferent, SimilarPhotos.threshold)
        XCTAssertGreaterThan(SimilarPhotos.distance(fp[0], fp[4])!, SimilarPhotos.threshold)
    }

    func testGroupsSimilarPhotos() throws {
        let urls = [try scene("a1.jpg"), try scene("a2.jpg", width: 900, quality: 0.8), try scene("a3.jpg", shift: 10),
                    try scene("b.jpg", hue: 0.05, seed: 3)]
        let groups = SimilarPhotos.findGroups(in: urls.map(entry)) { _ in }
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(Set(groups[0].map(\.name)), ["a1.jpg", "a2.jpg", "a3.jpg"])
    }
}
