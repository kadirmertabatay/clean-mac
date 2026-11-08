import QuickLook
import QuickLookThumbnailing
import SwiftUI

struct SimilarPhotosView: View {
    @EnvironmentObject var state: AppState
    @State private var selected = Set<String>()
    @State private var confirm = false
    @State private var previewURL: URL?

    private var groups: [[FileEntry]] {
        state.similarPhotoGroups.compactMap { g in
            let visible = g.filter { !state.isExcluded($0.id) }
            return visible.count > 1 ? visible : nil
        }
    }

    var body: some View {
        let groups = groups
        let selectedFiles = groups.flatMap { $0 }.filter { selected.contains($0.id) }
        let selectedSize = selectedFiles.reduce(Int64(0)) { $0 + $1.size }

        VStack(spacing: 0) {
            PageHeader(title: L("Similar Photos"),
                       subtitle: L("Burst shots and re-saved copies. Image analysis runs entirely on this Mac.")) {
                Button {
                    selected = []
                    Task { await state.findSimilarPhotos() }
                } label: { Label(state.similarPhotosReady ? L("Search Again") : L("Find Similar"), systemImage: "photo.stack") }
                    .disabled(state.isScanning || state.isFindingSimilar)
            }
            Divider()
            if state.isScanning {
                ScanningView()
            } else if state.isFindingSimilar {
                VStack(spacing: 14) {
                    ProgressView(value: state.similarProgress).frame(width: 320)
                    Text(L("Analyzing photos… \(state.similarProgress.formatted(.percent.precision(.fractionLength(0))))"))
                    Button(L("Stop")) { state.cancelScan() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.similarPhotosReady {
                EmptyStateView(icon: "photo.stack", title: L("Find similar photos"),
                               message: L("Photos in the scanned folder (excluding the Photos library) are grouped by visual similarity. No files are changed."),
                               actionTitle: L("Find Similar")) { Task { await state.findSimilarPhotos() } }
            } else if groups.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: L("No similar photos"),
                               message: L("No groups of very similar photos were found."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.first!.id) { group in groupRow(group) }
                    }
                    .padding(20)
                }
                Divider()
                HStack(spacing: 12) {
                    Text(L("\(groups.count) groups")).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Smart Select")) {
                        // Keep the largest (usually highest-quality) file in each group.
                        selected = Set(groups.flatMap { $0.dropFirst().map(\.id) })
                    }
                    .help(L("Keeps the largest file in each group and selects the others."))
                    Button(L("Clear Selection")) { selected = [] }.disabled(selected.isEmpty)
                    Button(L("Move to Trash (\(selectedFiles.count) · \(selectedSize.formattedBytes))"), role: .destructive) { confirm = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .disabled(selectedFiles.isEmpty || state.isRemoving
                                  || groups.contains { g in g.allSatisfy { selected.contains($0.id) } })
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .quickLookPreview($previewURL)
        .confirmationDialog(L("Move \(selectedFiles.count) photos to the Trash?"), isPresented: $confirm) {
            Button(L("Move to Trash (\(selectedSize.formattedBytes))"), role: .destructive) {
                let targets = groups.flatMap { g -> [RemovalTarget] in
                    let keep = g.filter { !selected.contains($0.id) }.map(\.url)
                    return g.filter { selected.contains($0.id) }.map {
                        RemovalTarget(url: $0.url, size: $0.size, expectedModified: $0.modified, keepAnyOf: keep)
                    }
                }
                selected = []
                Task { await state.remove(targets, permanently: false) }
            }
        } message: {
            Text(L("At least one photo from each group is kept. Since the photos are similar but not identical, review your selection; they can be restored from History."))
        }
    }

    private func groupRow(_ group: [FileEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("\(group.count) similar photos · \(group.first!.url.deletingLastPathComponent().abbreviatedPath)"))
                .font(.headline).lineLimit(1).truncationMode(.middle)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(group.enumerated()), id: \.element.id) { i, photo in
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack(alignment: .topLeading) {
                                Thumbnail(url: photo.url)
                                    .frame(width: 160, height: 120)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(selected.contains(photo.id) ? Color.red : Color.secondary.opacity(0.25),
                                                      lineWidth: selected.contains(photo.id) ? 3 : 1))
                                    .onTapGesture(count: 2) { previewURL = photo.url }
                                    .onTapGesture { toggle(photo.id) }
                                Checkbox(state: selected.contains(photo.id) ? .on : .off) { toggle(photo.id) }
                                    .padding(6)
                                if i == 0 {
                                    Text(L("largest")).font(.caption2.bold()).foregroundStyle(.white)
                                        .padding(.horizontal, 5).padding(.vertical, 2)
                                        .background(Color.green, in: Capsule())
                                        .padding(6)
                                        .frame(width: 160, alignment: .topTrailing)
                                }
                            }
                            Text(photo.name).font(.caption).lineLimit(1).truncationMode(.middle).frame(width: 160, alignment: .leading)
                            Text(photo.size.formattedBytes).font(.caption2).foregroundStyle(.secondary)
                        }
                        .contextMenu {
                            Button(L("Quick Look")) { previewURL = photo.url }
                            Button(L("Show in Finder")) { Finder.reveal([photo.url]) }
                            Button(L("Exclude")) { state.addExclusion(photo.url) }
                        }
                    }
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }
}

private struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            if let image {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .task(id: url) {
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 320, height: 240),
                                                       scale: 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = rep.nsImage
            }
        }
    }
}
