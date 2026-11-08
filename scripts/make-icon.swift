// Uygulama simgesini üretir: swift scripts/make-icon.swift <logo.png> <çıktı-klasörü>
// Logo kenarlardaki yarı saydam lekelerden temizlenir, kırpılır ve beyaz çerçeveli macOS simgesine yerleştirilir.
import AppKit

let args = CommandLine.arguments
let source = URL(fileURLWithPath: args.count > 1 ? args[1] : "Resources/logo.png")
let outDir = URL(fileURLWithPath: args.count > 2 ? args[2] : "Resources")

// MARK: - Logoyu temizle

func cleanedLogo(_ url: URL) -> CGImage {
    guard let img = NSImage(contentsOf: url), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Logo okunamadı: \(url.path)")
    }
    let w = cg.width, h = cg.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    // Belirgin (alfa > 120) piksellerden en büyük bağlı bileşen = logonun kendisi.
    let solid = (0..<(w * h)).map { px[$0 * 4 + 3] > 120 }
    var label = [Int32](repeating: 0, count: w * h)
    var best: Int32 = 0, bestCount = 0, next: Int32 = 1
    var stack: [Int] = []
    for start in 0..<(w * h) where solid[start] && label[start] == 0 {
        var count = 0
        label[start] = next
        stack.append(start)
        while let i = stack.popLast() {
            count += 1
            let x = i % w, y = i / w
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                let j = ny * w + nx
                if solid[j] && label[j] == 0 { label[j] = next; stack.append(j) }
            } }
        }
        if count > bestCount { bestCount = count; best = next }
        next += 1
    }

    // Kenar yumuşatmasını korumak için maskeyi 2 piksel genişlet; dışındaki her şeyi sil.
    var keep = label.map { $0 == best }
    for _ in 0..<2 {
        var grown = keep
        for y in 0..<h { for x in 0..<w where !keep[y * w + x] {
            if (x > 0 && keep[y * w + x - 1]) || (x < w - 1 && keep[y * w + x + 1])
                || (y > 0 && keep[(y - 1) * w + x]) || (y < h - 1 && keep[(y + 1) * w + x]) { grown[y * w + x] = true }
        } }
        keep = grown
    }
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w {
        let i = y * w + x
        if keep[i] && px[i * 4 + 3] > 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } else {
            px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; px[i * 4 + 3] = 0
        }
    } }
    let full = ctx.makeImage()!
    return full.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))!
}

let logo = cleanedLogo(source)

// MARK: - Simgeyi çiz

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let gctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = gctx
    gctx.imageInterpolation = .high
    let s = CGFloat(px)
    // macOS simge ızgarası: 1024'lük tuvalde 824'lük yuvarlatılmış kare.
    let tile = NSRect(x: s * 0.0977, y: s * 0.0977, width: s * 0.8047, height: s * 0.8047)
    let radius = tile.width * 0.225
    let path = NSBezierPath(roundedRect: tile, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = s * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.set()
    NSColor.white.setFill()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(colors: [.white, NSColor(calibratedWhite: 0.94, alpha: 1)])!.draw(in: path, angle: -90)
    NSColor(calibratedWhite: 0.82, alpha: 1).setStroke()
    path.lineWidth = max(1, s * 0.004)
    path.stroke()

    // Logoyu karenin %78'ine sığdır ve ortala.
    let box = tile.insetBy(dx: tile.width * 0.11, dy: tile.height * 0.11)
    let aspect = CGFloat(logo.width) / CGFloat(logo.height)
    var size = NSSize(width: box.width, height: box.width / aspect)
    if size.height > box.height { size = NSSize(width: box.height * aspect, height: box.height) }
    let rect = NSRect(x: box.midX - size.width / 2, y: box.midY - size.height / 2, width: size.width, height: size.height)
    gctx.cgContext.draw(logo, in: rect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = outDir.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! render(1024).write(to: outDir.appendingPathComponent("AppIcon-1024.png"))
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", outDir.appendingPathComponent("AppIcon.icns").path]
try! p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("AppIcon.icns oluşturuldu")
