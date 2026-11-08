import SwiftUI
import XCTest
@testable import CleanMac

@MainActor
final class SplashTests: XCTestCase {
    /// Renders the welcome screen as an image; writes it to a file if CLEANMAC_SPLASH_PNG is set.
    func testSplashRenders() throws {
        for scheme in [ColorScheme.light, .dark] {
            let logo = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Resources/AppIcon-1024.png")
            let view = SplashView(disk: DiskInfo.current(), icon: NSImage(contentsOf: logo), settled: true) {}
                .frame(width: 1040, height: 660)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, 1040)
            if let out = ProcessInfo.processInfo.environment["CLEANMAC_SPLASH_PNG"],
               let tiff = image.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                try png.write(to: URL(fileURLWithPath: out + "-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }
}
