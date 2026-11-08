import SwiftUI

struct Recommendation: Identifiable {
    enum Level: Int {
        case critical, warning, suggestion, info, good

        var color: Color {
            switch self {
            case .critical: .red
            case .warning: .orange
            case .suggestion: .accentColor
            case .info: .purple
            case .good: .green
            }
        }
    }

    enum Action {
        case open(AppSection)
        case openStaleLargeFiles
        case cleanJunk(String)
        case openFolder(FileNode)
        case fullDiskAccess
        case storageSettings
    }

    let id: String
    let level: Level
    let icon: String
    let title: String
    let detail: String
    var size: Int64?
    var action: Action?
    var actionTitle: String?
}

/// Rule-based recommendation engine that runs entirely locally.
extension AppState {
    static let staleDays = 180

    var staleLargeFiles: [FileEntry] {
        let cutoff = Date().addingTimeInterval(-Double(Self.staleDays) * 86_400)
        return files.filter {
            !$0.isProtected && !isExcluded($0.id) && $0.size >= 100_000_000 && ($0.lastUsed ?? .distantPast) < cutoff
        }
    }

    var visibleDuplicateWaste: Int64 {
        duplicateGroups.reduce(0) { total, g in
            let n = g.files.filter { !$0.isProtected && !isExcluded($0.id) }.count
            return total + g.size * Int64(max(n - 1, 0))
        }
    }

    var safeJunkTotal: Int64 {
        junkCategories.filter { $0.safety == .safe }.reduce(0) { $0 + $1.size }
    }

    var reviewJunkTotal: Int64 {
        junkCategories.filter { $0.safety == .review }.reduce(0) { $0 + $1.size }
    }

    var devArtifactTotal: Int64 { visibleDevArtifacts.reduce(0) { $0 + $1.size } }

    var hasAnalysisData: Bool { junkReady || rootNode != nil }

    var recommendations: [Recommendation] {
        var recs: [Recommendation] = []

        if let d = disk {
            let pct = d.freeFraction.formatted(.percent.precision(.fractionLength(0)))
            if d.freeFraction < 0.10 {
                recs.append(.init(id: "disk", level: .critical, icon: "exclamationmark.octagon.fill",
                                  title: L("Disk almost full"),
                                  detail: L("Only \(d.available.formattedBytes) (\(pct)) of free space left. At least 15% free space is recommended for macOS to run smoothly. Start with the suggestions below."),
                                  action: .storageSettings, actionTitle: L("Storage Settings")))
            } else if d.freeFraction < 0.20 {
                recs.append(.init(id: "disk", level: .warning, icon: "exclamationmark.triangle.fill",
                                  title: L("Free space is running low"),
                                  detail: L("\(d.available.formattedBytes) (\(pct)) free. A little cleanup would help.")))
            } else {
                recs.append(.init(id: "disk", level: .good, icon: "checkmark.seal.fill",
                                  title: L("Disk is in good shape"),
                                  detail: L("\(d.available.formattedBytes) (\(pct)) of your \(d.total.formattedBytes) disk is free.")))
            }
        }

        if !hasFullDiskAccess {
            recs.append(.init(id: "fda", level: .info, icon: "lock.shield",
                              title: L("Full Disk Access not granted"),
                              detail: L("Some folders like the Trash, Mail and device backups can’t be read. For more accurate results you can give CleanMac Full Disk Access (optional)."),
                              action: .fullDiskAccess, actionTitle: L("Open Settings")))
        }

        if junkReady {
            for c in junkCategories where c.size >= 50_000_000 {
                let safe = c.safety == .safe
                recs.append(.init(
                    id: "junk-\(c.id)", level: safe ? .suggestion : .info, icon: c.icon,
                    title: "\(c.title): \(c.size.formattedBytes)",
                    detail: safe ? c.detail : c.detail + L(" I recommend reviewing the items one by one."),
                    size: c.size,
                    action: safe ? .cleanJunk(c.id) : .open(.junk),
                    actionTitle: safe ? (c.permanentOnly ? L("Empty") : L("Clean")) : L("Review")))
            }
        }

        if rootNode != nil {
            if devArtifactTotal >= 200_000_000 {
                recs.append(.init(id: "dev", level: .suggestion, icon: "shippingbox.fill",
                                  title: L("\(visibleDevArtifacts.count) project dependency folders: \(devArtifactTotal.formattedBytes)"),
                                  detail: L("Folders like node_modules, .venv and Pods. You can delete the ones from projects you’re not working on; they come back with npm install / pip install when needed."),
                                  size: devArtifactTotal, action: .open(.developer), actionTitle: L("Review")))
            }
            let stale = staleLargeFiles
            if !stale.isEmpty {
                let total = stale.reduce(Int64(0)) { $0 + $1.size }
                recs.append(.init(id: "stale", level: .suggestion, icon: "clock.badge.questionmark",
                                  title: L("\(stale.count) large files unused for \(Self.staleDays / 30)+ months: \(total.formattedBytes)"),
                                  detail: L("Files over 100 MB that haven’t been opened in a long time. Consider moving them to an external disk or the cloud."),
                                  size: total, action: .openStaleLargeFiles, actionTitle: L("Show")))
            }
            let huge = files.filter { !$0.isProtected && !isExcluded($0.id) && $0.size >= 1_000_000_000 }.sorted { $0.size > $1.size }
            if !huge.isEmpty {
                let names = huge.prefix(3).map { "\($0.name) (\($0.size.formattedBytes))" }.joined(separator: ", ")
                recs.append(.init(id: "huge", level: .info, icon: "doc.badge.arrow.up",
                                  title: L("\(huge.count) files over 1 GB"),
                                  detail: L("Largest: \(names)."),
                                  size: huge.reduce(0) { $0 + $1.size }, action: .open(.largeFiles), actionTitle: L("Show List")))
            }
            if let root = rootNode, let top = root.children.first(where: { !$0.isAggregate && $0.isDirectory }) {
                recs.append(.init(id: "top", level: .info, icon: "folder.fill",
                                  title: L("Largest folder: \(top.url.abbreviatedPath)"),
                                  detail: L("\(top.size.formattedBytes) · \(top.fileCount.formatted()) files. Look inside to see what grew."),
                                  size: top.size, action: .openFolder(top), actionTitle: L("Open")))
            }
        }

        // When the entire Mac was scanned, explain the space the scan couldn't see.
        if let root = rootNode, root.url.path == "/", let d = disk, d.used - root.size > 5_000_000_000 {
            let hidden = d.used - root.size
            recs.append(.init(id: "hidden", level: .info, icon: "eye.slash",
                              title: L("\(hidden.formattedBytes) not visible to the scan"),
                              detail: L("This space is usually local Time Machine snapshots, purgeable data managed by macOS, system volumes, or folders that couldn’t be read due to missing permissions (\(lastScan?.unreadable ?? 0) folders couldn’t be read). Granting Full Disk Access and checking `tmutil listlocalsnapshots /` helps."),
                              size: hidden, action: .open(.storage), actionTitle: L("See Breakdown")))
        }

        let appCutoff = Date().addingTimeInterval(-Double(Self.staleDays) * 86_400)
        let unusedApps = apps.filter { !$0.isApple && $0.lastUsed != nil && $0.lastUsedSort < appCutoff && $0.size > 50_000_000 }
        if !unusedApps.isEmpty {
            let total = unusedApps.reduce(Int64(0)) { $0 + $1.size }
            let names = unusedApps.sorted { $0.size > $1.size }.prefix(3).map(\.name).joined(separator: ", ")
            recs.append(.init(id: "apps", level: .suggestion, icon: "square.grid.3x3",
                              title: L("\(unusedApps.count) apps not opened in 6+ months: \(total.formattedBytes)"),
                              detail: L("Largest: \(names). You can remove them together with their leftover files."),
                              size: total, action: .open(.apps), actionTitle: L("Review")))
        }

        if let docker = apps.first(where: { $0.bundleID == "com.docker.docker" }) {
            let data = dockerDataSize
            if data > 5_000_000_000 {
                recs.append(.init(id: "docker", level: .suggestion, icon: "cube.box",
                                  title: L("Docker data takes up \(data.formattedBytes)"),
                                  detail: L("\(docker.name) keeps images, containers and the build cache in a single virtual disk. You can clean up unused items, or remove Docker entirely if you don’t use it."),
                                  size: data, action: .open(.docker), actionTitle: L("Review")))
            }
        }

        if scanSnapshots.count >= 2 {
            let diff = GrowthDiff.compute(old: scanSnapshots[1], new: scanSnapshots[0])
            if diff.totalDelta >= 1_000_000_000, let top = diff.grown.first {
                recs.append(.init(id: "growth", level: .info, icon: "chart.line.uptrend.xyaxis",
                                  title: L("Grew by \(diff.totalDelta.formattedBytes) since the previous scan"),
                                  detail: L("Grew the most: \(top.url.abbreviatedPath) (+\(top.delta.formattedBytes)), compared with the scan from \(diff.from.formatted(.relative(presentation: .named)))."),
                                  size: diff.totalDelta, action: .open(.growth), actionTitle: L("Compare")))
            }
        }

        if let s = storage, !s.snapshots.isEmpty {
            recs.append(.init(id: "snapshots", level: .suggestion, icon: "clock.arrow.circlepath",
                              title: L("\(s.snapshots.count) local Time Machine snapshots"),
                              detail: L("These snapshots use space the scan can’t see. If you have external backups, they can be deleted safely."),
                              action: .open(.storage), actionTitle: L("Review")))
        }

        if duplicatesReady, visibleDuplicateWaste >= 50_000_000 {
            recs.append(.init(id: "dups", level: .suggestion, icon: "doc.on.doc.fill",
                              title: L("Duplicate files waste \(visibleDuplicateWaste.formattedBytes)"),
                              detail: L("Multiple copies with the same content were found. You can keep one from each group and remove the others."),
                              size: visibleDuplicateWaste, action: .open(.duplicates), actionTitle: L("Review")))
        }

        return recs.sorted {
            if $0.level != $1.level { return $0.level.rawValue < $1.level.rawValue }
            return ($0.size ?? 0) > ($1.size ?? 0)
        }
    }
}

struct AssistantView: View {
    @EnvironmentObject var state: AppState
    @State private var pendingClean: JunkCategory?
    @AppStorage("permanentDelete") private var permanentDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                if state.isAnalyzing { progressCard }
                if state.hasAnalysisData { summary }
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("Suggestions")).font(.title2.bold())
                    ForEach(state.recommendations) { rec in
                        RecommendationRow(rec: rec) { handle($0) }
                    }
                    if !state.hasAnalysisData && !state.isAnalyzing {
                        Text(L("Suggestions tailored to your Mac will appear here once you start the analysis."))
                            .foregroundStyle(.secondary)
                    }
                }
                tips
            }
            .padding(24)
            .frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog(pendingClean.map { L("Clean \($0.title)?") } ?? "",
                            isPresented: Binding(get: { pendingClean != nil }, set: { if !$0 { pendingClean = nil } }),
                            presenting: pendingClean) { category in
            Button(category.permanentOnly ? L("Empty Trash") : L("Clean (\(category.size.formattedBytes))"), role: .destructive) {
                Task { await state.cleanJunkCategory(category.id) }
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: { category in
            let protectedCount = category.items.filter { state.isSmartProtected($0.id) }.count
            Text((protectedCount > 0 ? L("\(protectedCount) items will be skipped because of Smart Cleanup protections. ") : "") + (category.permanentOnly || permanentDelete
                 ? L("\(category.items.count) items will be deleted permanently. This can’t be undone.")
                 : L("\(category.items.count) items will be moved to the Trash. Empty the Trash later to free the space.")))
        }
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
            VStack(alignment: .leading, spacing: 8) {
                Text(L("Hi! I’m your storage assistant.")).font(.title.bold())
                Text(L("I scan your Mac to find what’s taking up space, suggest what can be safely deleted and show duplicate files. Everything runs on this computer; nothing is deleted without your approval, and by default everything goes to the Trash."))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button {
                        Task { await state.runFullAnalysis() }
                    } label: {
                        Label(state.lastAnalysis == nil ? L("Start Full Analysis") : L("Refresh Analysis"), systemImage: "wand.and.stars")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(state.isAnalyzing || state.isScanning)

                    Text(L("Scope:")).foregroundStyle(.secondary).padding(.leading, 6)
                    ScanScopeMenu()
                        .controlSize(.large)
                }
                .padding(.top, 4)
            }
        }
    }

    private var progressCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(state.analysisStep).font(.headline)
                    Spacer()
                    Button(L("Stop")) { state.cancelScan() }
                }
                if let p = state.scanProgress {
                    Text(L("\(p.files.formatted()) files · \(p.bytes.formattedBytes) — \(URL(fileURLWithPath: p.currentPath).abbreviatedPath)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if state.isFindingDuplicates {
                    ProgressView(value: state.duplicateProgress)
                }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 14) {
            SummaryTile(title: L("Safe to clean"), value: state.safeJunkTotal, color: .green,
                        note: L("Caches, logs, developer leftovers"))
            SummaryTile(title: L("Worth reviewing"), value: state.reviewJunkTotal + state.devArtifactTotal + state.visibleDuplicateWaste,
                        color: .orange, note: L("Downloads, dependencies, duplicates"))
            if let d = state.disk {
                SummaryTile(title: L("Free space now"), value: d.available, color: usageColor(d.usedFraction),
                            note: L("of your \(d.total.formattedBytes) disk"))
            }
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L("Tips")).font(.title2.bold())
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    tip("internaldrive", L("Also check the recommendations in System Settings › General › Storage."))
                    tip("icloud", L("If “Optimize Mac Storage” is on in iCloud Drive, rarely used files are removed from the Mac."))
                    tip("clock.arrow.circlepath", L("Local Time Machine snapshots: run `tmutil listlocalsnapshots /` in Terminal"))
                    tip("shippingbox", L("If you use Docker, `docker system prune -a` removes unused images."))
                    tip("iphone", L("For old simulators: `xcrun simctl delete unavailable`"))
                }
            }
        }
    }

    private func tip(_ icon: String, _ text: String) -> some View {
        Label { Text(.init(text)) } icon: { Image(systemName: icon).foregroundStyle(Color.accentColor) }
    }

    private func handle(_ action: Recommendation.Action) {
        switch action {
        case .open(let s): state.section = s
        case .openStaleLargeFiles:
            state.largeFilesStaleOnly = true
            state.section = .largeFiles
        case .cleanJunk(let id): pendingClean = state.junkCategories.first { $0.id == id }
        case .openFolder(let node):
            state.currentNode = node
            state.section = .explorer
        case .fullDiskAccess: Finder.openFullDiskAccessSettings()
        case .storageSettings: Finder.openStorageSettings()
        }
    }
}

private struct SummaryTile: View {
    let title: String
    let value: Int64
    let color: Color
    let note: String

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline).foregroundStyle(.secondary)
                Text(value.formattedBytes).font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(color)
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct RecommendationRow: View {
    let rec: Recommendation
    let onAction: (Recommendation.Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: rec.icon)
                .font(.title3)
                .foregroundStyle(rec.level.color)
                .frame(width: 36, height: 36)
                .background(rec.level.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(rec.title).font(.headline)
                Text(.init(rec.detail)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if let action = rec.action, let title = rec.actionTitle {
                Button(title) { onAction(action) }
                    .controlSize(.regular)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(rec.level.color.opacity(0.25)))
    }
}
