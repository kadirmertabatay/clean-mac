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
            PageHeader(title: "Benzer Fotoğraflar",
                       subtitle: "Seri çekimler ve yeniden kaydedilmiş kopyalar. Görüntü analizi tamamen bu Mac'te yapılır.") {
                Button {
                    selected = []
                    Task { await state.findSimilarPhotos() }
                } label: { Label(state.similarPhotosReady ? "Yeniden Ara" : "Benzerleri Bul", systemImage: "photo.stack") }
                    .disabled(state.isScanning || state.isFindingSimilar)
            }
            Divider()
            if state.isScanning {
                ScanningView()
            } else if state.isFindingSimilar {
                VStack(spacing: 14) {
                    ProgressView(value: state.similarProgress).frame(width: 320)
                    Text("Fotoğraflar analiz ediliyor… \(state.similarProgress.formatted(.percent.precision(.fractionLength(0))))")
                    Button("Durdur") { state.cancelScan() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !state.similarPhotosReady {
                EmptyStateView(icon: "photo.stack", title: "Benzer fotoğrafları bul",
                               message: "Taranan klasördeki fotoğraflar (Fotoğraflar arşivi hariç) görsel benzerliğe göre gruplanır. Hiçbir dosya değiştirilmez.",
                               actionTitle: "Benzerleri Bul") { Task { await state.findSimilarPhotos() } }
            } else if groups.isEmpty {
                EmptyStateView(icon: "checkmark.circle", title: "Benzer fotoğraf yok",
                               message: "Birbirine çok benzeyen fotoğraf grubu bulunamadı.")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(groups, id: \.first!.id) { group in groupRow(group) }
                    }
                    .padding(20)
                }
                Divider()
                HStack(spacing: 12) {
                    Text("\(groups.count) grup").foregroundStyle(.secondary)
                    Spacer()
                    Button("Akıllı Seç") {
                        // Her gruptaki en büyük (genellikle en yüksek kaliteli) dosyayı koru.
                        selected = Set(groups.flatMap { $0.dropFirst().map(\.id) })
                    }
                    .help("Her grupta en büyük dosyayı korur, diğerlerini seçer.")
                    Button("Seçimi Temizle") { selected = [] }.disabled(selected.isEmpty)
                    Button("Çöp Kutusu'na Taşı (\(selectedFiles.count) · \(selectedSize.formattedBytes))", role: .destructive) { confirm = true }
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
        .confirmationDialog("\(selectedFiles.count) fotoğraf Çöp Kutusu'na taşınsın mı?", isPresented: $confirm) {
            Button("Çöp Kutusu'na Taşı (\(selectedSize.formattedBytes))", role: .destructive) {
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
            Text("Her gruptan en az bir fotoğraf korunur. Benzer ama aynı olmayan fotoğraflar olduğu için seçimini gözden geçir; Geçmiş'ten geri alınabilir.")
        }
    }

    private func groupRow(_ group: [FileEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(group.count) benzer fotoğraf · \(group.first!.url.deletingLastPathComponent().abbreviatedPath)")
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
                                    Text("en büyük").font(.caption2.bold()).foregroundStyle(.white)
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
                            Button("Hızlı Bakış") { previewURL = photo.url }
                            Button("Finder'da Göster") { Finder.reveal([photo.url]) }
                            Button("Hariç Tut") { state.addExclusion(photo.url) }
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
