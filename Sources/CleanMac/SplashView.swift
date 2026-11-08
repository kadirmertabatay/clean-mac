import AppKit
import SwiftUI

/// The welcome screen shown once while the app launches.
/// The icon springs in, a scan ring spins around it and sparkles appear;
/// disk info is shown on the bottom line once ready. Clicking dismisses it immediately.
struct SplashView: View {
    let disk: DiskInfo?
    let icon: NSImage
    var onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconIn = false
    @State private var ringTrim: CGFloat = 0
    @State private var ringRotation: Double = 0
    @State private var textIn = false
    @State private var sparkle = false
    @State private var statusIndex = 0

    private let statuses = [L("Getting ready…"), L("Reading disk…"), L("Assistant ready")]
    static let duration: Double = 2.2

    init(disk: DiskInfo?, icon: NSImage? = nil, settled: Bool = false, onFinish: @escaping () -> Void) {
        self.disk = disk
        self.icon = icon ?? NSApp?.applicationIconImage ?? NSImage(named: NSImage.applicationIconName) ?? NSImage()
        self.onFinish = onFinish
        // settled: the finished state of the animations (for rendering images in tests)
        if settled {
            _iconIn = State(initialValue: true); _ringTrim = State(initialValue: 1)
            _textIn = State(initialValue: true); _sparkle = State(initialValue: true)
        }
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 22) {
                ZStack {
                    // Scan ring
                    Circle()
                        .stroke(Color.accentColor.opacity(0.12), lineWidth: 5)
                        .frame(width: 196, height: 196)
                    Circle()
                        .trim(from: 0, to: ringTrim)
                        .stroke(
                            AngularGradient(colors: [.cyan.opacity(0.1), .cyan, .blue, .mint], center: .center),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round)
                        )
                        .frame(width: 196, height: 196)
                        .rotationEffect(.degrees(-90 + ringRotation))

                    // Icon
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 148, height: 148)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .scaleEffect(iconIn ? 1 : 0.6)
                        .opacity(iconIn ? 1 : 0)

                    // Sparkles
                    ForEach(Self.sparkles.indices, id: \.self) { i in
                        let s = Self.sparkles[i]
                        Image(systemName: "sparkle")
                            .font(.system(size: s.size, weight: .bold))
                            .foregroundStyle(.white, .cyan)
                            .shadow(color: .cyan.opacity(0.8), radius: 6)
                            .offset(x: s.x, y: s.y)
                            .scaleEffect(sparkle ? 1 : 0.2)
                            .opacity(sparkle ? 1 : 0)
                            .animation(
                                reduceMotion ? nil :
                                    .easeInOut(duration: 0.7).repeatForever(autoreverses: true).delay(s.delay),
                                value: sparkle
                            )
                    }
                }

                VStack(spacing: 6) {
                    Text("CleanMac")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [.primary, .primary.opacity(0.7)], startPoint: .top, endPoint: .bottom)
                        )
                    Text(L("A local storage assistant for your Mac"))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .opacity(textIn ? 1 : 0)
                .offset(y: textIn ? 0 : 12)

                VStack(spacing: 10) {
                    Text(statuses[statusIndex])
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                        .id(statusIndex)
                        .transition(.opacity)
                    if let disk {
                        HStack(spacing: 8) {
                            Image(systemName: "internaldrive")
                            Text(L("\(disk.available.formattedBytes) free · \(disk.total.formattedBytes)"))
                                .monospacedDigit()
                        }
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .transition(.opacity)
                    }
                }
                .frame(height: 44)
                .opacity(textIn ? 1 : 0)
            }

            VStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                    Text(L("Fully local · No data ever leaves your Mac"))
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 22)
                .opacity(textIn ? 1 : 0)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinish() }
        .task { await run() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("CleanMac is opening"))
    }

    private var background: some View {
        ZStack {
            Rectangle().fill(.background)
            RadialGradient(
                colors: [Color.cyan.opacity(0.22), Color.blue.opacity(0.08), .clear],
                center: .center, startRadius: 40, endRadius: 520
            )
            .scaleEffect(iconIn ? 1 : 0.7)
        }
        .ignoresSafeArea()
    }

    private func run() async {
        if reduceMotion {
            iconIn = true; textIn = true; ringTrim = 1
        } else {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.62)) { iconIn = true }
            withAnimation(.easeInOut(duration: 1.6)) { ringTrim = 1 }
            withAnimation(.linear(duration: Self.duration).repeatForever(autoreverses: false)) { ringRotation = 360 }
            withAnimation(.easeOut(duration: 0.5).delay(0.25)) { textIn = true }
            try? await Task.sleep(for: .milliseconds(350))
            sparkle = true
        }
        let step = Self.duration / Double(statuses.count)
        for i in 1..<statuses.count {
            try? await Task.sleep(for: .seconds(step))
            withAnimation(.easeInOut(duration: 0.25)) { statusIndex = i }
        }
        try? await Task.sleep(for: .seconds(step * 0.6))
        onFinish()
    }

    private struct Sparkle { let x: CGFloat; let y: CGFloat; let size: CGFloat; let delay: Double }
    private static let sparkles: [Sparkle] = [
        .init(x: 72, y: -78, size: 22, delay: 0.0),
        .init(x: -84, y: -50, size: 14, delay: 0.35),
        .init(x: 90, y: 40, size: 12, delay: 0.6),
        .init(x: -66, y: 74, size: 18, delay: 0.2),
        .init(x: 6, y: -104, size: 10, delay: 0.85),
    ]
}
