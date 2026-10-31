import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Temizlik Geçmişi",
                       subtitle: "CleanMac ile kaldırılan her öğe. Çöp Kutusu'nda duranları tek tıkla eski yerine geri alabilirsin.") {
                Button("Geçmişi Temizle") { confirmClear = true }
                    .disabled(state.history.isEmpty)
            }
            Divider()
            if state.history.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", title: "Henüz temizlik yapılmadı",
                               message: "Bir şey sildiğinde ya da Çöp Kutusu'na taşıdığında burada listelenir.")
            } else {
                List {
                    ForEach(groupedByDay, id: \.0) { day, records in
                        Section(day.formatted(date: .complete, time: .omitted)) {
                            ForEach(records) { HistoryRow(record: $0) }
                        }
                    }
                }
                Divider()
                HStack {
                    let trashed = state.history.filter { !$0.isPermanent && !$0.restored }
                    Text("\(state.history.count) kayıt · Çöp Kutusu'na taşınan \(trashed.reduce(Int64(0)) { $0 + $1.size }.formattedBytes)")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .confirmationDialog("Geçmiş temizlensin mi?", isPresented: $confirmClear) {
            Button("Geçmişi Temizle", role: .destructive) { state.clearHistory() }
        } message: {
            Text("Yalnızca kayıtlar silinir; Çöp Kutusu'ndaki dosyalara dokunulmaz.")
        }
    }

    private var groupedByDay: [(Date, [HistoryRecord])] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: state.history) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { ($0, groups[$0]!) }
    }
}

private struct HistoryRow: View {
    @EnvironmentObject var state: AppState
    let record: HistoryRecord

    var body: some View {
        let inTrash = state.isInTrash(record)
        HStack(spacing: 10) {
            Image(systemName: record.restored ? "arrow.uturn.backward.circle.fill"
                  : record.isPermanent ? "xmark.bin.fill" : "trash.fill")
                .foregroundStyle(record.restored ? Color.green : record.isPermanent ? Color.red : Color.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name).lineLimit(1)
                Text(URL(fileURLWithPath: record.originalPath).deletingLastPathComponent().abbreviatedPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            Text(record.date.formatted(date: .omitted, time: .shortened)).font(.caption).foregroundStyle(.secondary)
            Text(record.size.formattedBytes).monospacedDigit().frame(width: 80, alignment: .trailing)
            Group {
                if record.restored {
                    Text("Geri alındı").foregroundStyle(.green)
                } else if record.isPermanent {
                    Text("Kalıcı silindi").foregroundStyle(.secondary)
                } else if inTrash {
                    Button("Geri Al") { state.restore(record) }
                } else {
                    Text("Çöpten boşaltılmış").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .frame(width: 130, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }
}

struct ExclusionsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: "Hariç Tutulanlar",
                       subtitle: "Buradaki klasör ve dosyalar asistan tarafından önerilmez, listelerde gösterilmez ve CleanMac tarafından asla silinmez.") {
                Button {
                    state.chooseExclusion()
                } label: { Label("Ekle…", systemImage: "plus") }
            }
            Divider()
            if state.excludedPaths.isEmpty {
                EmptyStateView(icon: "lock.shield", title: "Hariç tutulan bir şey yok",
                               message: "Aktif projelerini, önemli arşivlerini ya da dokunulmasını istemediğin klasörleri ekle. Listelerde sağ tıklayıp \"Hariç Tut\" diyerek de ekleyebilirsin.",
                               actionTitle: "Klasör Ekle") { state.chooseExclusion() }
            } else {
                List {
                    ForEach(state.excludedPaths, id: \.self) { path in
                        HStack(spacing: 10) {
                            FileIconView(url: URL(fileURLWithPath: path), size: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(URL(fileURLWithPath: path).lastPathComponent)
                                Text(URL(fileURLWithPath: path).abbreviatedPath).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !FileManager.default.fileExists(atPath: path) {
                                Text("bulunamadı").font(.caption).foregroundStyle(.orange)
                            }
                            Button { Finder.reveal([URL(fileURLWithPath: path)]) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless)
                            Button(role: .destructive) { state.removeExclusion(path) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help("Listeden çıkar")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}
