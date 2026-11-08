import AppKit
import SwiftUI

enum Finder {
    static func reveal(_ urls: [URL]) {
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    static func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    static func copyPaths(_ urls: [URL]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(urls.map(\.path).joined(separator: "\n"), forType: .string)
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openStorageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.Storage") {
            NSWorkspace.shared.open(url)
        }
    }
}

func usageColor(_ fraction: Double) -> Color {
    fraction > 0.9 ? .red : fraction > 0.8 ? .orange : .accentColor
}

struct FileIconView: View {
    let url: URL
    var size: CGFloat = 18

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct UsageBar: View {
    let fraction: Double
    var color: Color = .accentColor
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(color.gradient)
                    .frame(width: max(2, g.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title.bold())
                Text(subtitle).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ScanningView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text(L("Scanning \(state.scanRoot.abbreviatedPath)…")).font(.title3.bold())
            if let p = state.scanProgress {
                Text(L("\(p.files.formatted()) files · \(p.bytes.formattedBytes)"))
                    .monospacedDigit()
                Text(URL(fileURLWithPath: p.currentPath).abbreviatedPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 520)
            }
            Button(L("Stop")) { state.cancelScan() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Scan scope picker: home folder, entire Mac or another folder.
struct ScanScopeMenu: View {
    @EnvironmentObject var state: AppState
    var onChange: () -> Void = {}

    var body: some View {
        Menu {
            Button { select(AppState.home) } label: { Label(L("Home Folder (~)"), systemImage: "house") }
            Button { select(AppState.wholeMac) } label: { Label(L("Entire Mac (/)"), systemImage: "internaldrive") }
            Divider()
            Button {
                if state.chooseScanRoot() { onChange() }
            } label: { Label(L("Other Folder…"), systemImage: "folder") }
        } label: {
            Label(state.scanScopeTitle, systemImage: state.scanScopeIcon)
        }
        .fixedSize()
        .disabled(state.isScanning || state.isAnalyzing)
        .help(L("Area to scan: \(state.scanRoot.path)"))
    }

    private func select(_ url: URL) {
        state.scanRoot = url
        onChange()
    }
}

struct Checkbox: View {
    enum CheckState { case on, off, mixed }

    let state: CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .on ? "checkmark.square.fill" : state == .mixed ? "minus.square.fill" : "square")
                .font(.system(size: 15))
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.plain)
    }
}

struct SafetyBadge: View {
    let safety: JunkSafety

    var body: some View {
        let color: Color = safety == .safe ? .green : .orange
        Text(safety.title)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

struct ToastView: View {
    let toast: AppState.Toast

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(toast.isError ? .orange : .green)
            Text(toast.message)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 8, y: 2)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.secondary.opacity(0.15)))
    }
}
