import SwiftUI

/// Squarified treemap yerleşimi (Bruls, Huizing, van Wijk). Değerler büyükten küçüğe sıralı olmalı.
enum Treemap {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { max($0, 0) * scale }
        var remaining = rect
        var i = 0
        while i < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var row = [i]
            var j = i + 1
            while j < areas.count, worst(row.map { areas[$0] } + [areas[j]], side) <= worst(row.map { areas[$0] }, side) {
                row.append(j)
                j += 1
            }
            let rowArea = row.reduce(0) { $0 + areas[$1] }
            if remaining.width >= remaining.height {
                let w = CGFloat(rowArea / Double(remaining.height))
                var y = remaining.minY
                for k in row {
                    let h = CGFloat(areas[k]) / max(w, .leastNonzeroMagnitude)
                    result[k] = CGRect(x: remaining.minX, y: y, width: w, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + w, y: remaining.minY, width: max(remaining.width - w, 0), height: remaining.height)
            } else {
                let h = CGFloat(rowArea / Double(remaining.width))
                var x = remaining.minX
                for k in row {
                    let w = CGFloat(areas[k]) / max(h, .leastNonzeroMagnitude)
                    result[k] = CGRect(x: x, y: remaining.minY, width: w, height: h)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + h, width: remaining.width, height: max(remaining.height - h, 0))
            }
            i = j
        }
        return result
    }

    private static func worst(_ row: [Double], _ side: Double) -> Double {
        let s = row.reduce(0, +)
        guard s > 0, side > 0, let mx = row.max(), let mn = row.min(), mn > 0 else { return .infinity }
        return max(side * side * mx / (s * s), (s * s) / (side * side * mn))
    }
}

struct TreemapView: View {
    @EnvironmentObject var state: AppState
    let node: FileNode
    var onRemove: (FileNode) -> Void
    @State private var hovered: FileNode?
    @State private var previewURL: URL?

    private static let maxItems = 120

    private struct Tile {
        let node: FileNode
        let rect: CGRect
        let inner: [(FileNode, CGRect)]
    }

    private func tiles(in size: CGSize) -> [Tile] {
        let items = Array(node.children.filter { $0.size > 0 }.prefix(Self.maxItems))
        let rects = Treemap.layout(items.map { Double($0.size) }, in: CGRect(origin: .zero, size: size))
        return zip(items, rects).map { child, rect in
            // Yeterince büyük klasörlerin içini bir seviye daha göster.
            var inner: [(FileNode, CGRect)] = []
            if child.isDirectory, !child.isAggregate, rect.width > 90, rect.height > 60 {
                let content = rect.insetBy(dx: 3, dy: 3).offsetBy(dx: 0, dy: 8).insetBy(dx: 0, dy: 8)
                let grand = Array(child.children.filter { $0.size > 0 }.prefix(40))
                inner = Array(zip(grand, Treemap.layout(grand.map { Double($0.size) }, in: content)))
            }
            return Tile(node: child, rect: rect, inner: inner)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let tiles = tiles(in: geo.size)
            ZStack(alignment: .bottomLeading) {
                Canvas { ctx, _ in
                    for (i, t) in tiles.enumerated() {
                        let r = t.rect.insetBy(dx: 1, dy: 1)
                        guard r.width > 0, r.height > 0 else { continue }
                        let base = color(for: t.node, index: i)
                        ctx.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(base.opacity(t.node === hovered ? 1 : 0.85)))
                        for (g, gr) in t.inner {
                            let ir = gr.insetBy(dx: 0.75, dy: 0.75)
                            guard ir.width > 1, ir.height > 1 else { continue }
                            ctx.fill(Path(roundedRect: ir, cornerRadius: 2), with: .color(.white.opacity(g.isDirectory ? 0.16 : 0.08)))
                        }
                        if r.width > 60, r.height > 22 {
                            let label = Text("\(t.node.name)  \(t.node.size.formattedBytes)")
                                .font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            ctx.draw(label, in: CGRect(x: r.minX + 6, y: r.minY + 4, width: r.width - 12, height: 14))
                        }
                    }
                }
                .onContinuousHover { phase in
                    if case .active(let p) = phase {
                        hovered = tiles.first { $0.rect.contains(p) }?.node
                    } else {
                        hovered = nil
                    }
                }
                .onTapGesture(count: 2) { open(hovered) }
                .contextMenu {
                    if let h = hovered, !h.isAggregate {
                        if h.canDrillDown { Button("Aç") { open(h) } }
                        Button("Hızlı Bakış") { previewURL = h.url }
                        Button("Finder'da Göster") { Finder.reveal([h.url]) }
                        Button("Hariç Tut") { state.addExclusion(h.url) }
                        Divider()
                        Button("Çöp Kutusu'na Taşı…", role: .destructive) { onRemove(h) }
                    }
                }
                .quickLookPreview($previewURL)

                if let h = hovered {
                    HStack(spacing: 8) {
                        if h.isAggregate { Image(systemName: "square.stack.3d.up") } else { FileIconView(url: h.url, size: 16) }
                        Text(h.isAggregate ? h.name : h.url.abbreviatedPath).lineLimit(1).truncationMode(.middle)
                        Text(h.size.formattedBytes).bold()
                        if node.size > 0 {
                            Text((Double(h.size) / Double(node.size)).formatted(.percent.precision(.fractionLength(1))))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(10)
                    .allowsHitTesting(false)
                }
            }
        }
        .padding(8)
    }

    private func open(_ n: FileNode?) {
        guard let n, !n.isAggregate else { return }
        if n.canDrillDown { state.currentNode = n } else { Finder.reveal([n.url]) }
    }

    private static let folderPalette: [Color] = [.blue, .indigo, .teal, .cyan, .mint, .purple]

    private func color(for n: FileNode, index: Int) -> Color {
        if n.isAggregate { return .gray }
        if n.isDirectory { return Self.folderPalette[index % Self.folderPalette.count] }
        switch FileKind.of(n.url.pathExtension.lowercased()) {
        case .video: return .purple
        case .audio: return .pink
        case .image: return .green
        case .archive: return .orange
        case .diskImage: return .red
        case .document: return .blue
        case .application: return .teal
        case .other: return .gray
        }
    }
}
