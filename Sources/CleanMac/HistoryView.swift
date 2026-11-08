import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var state: AppState
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(title: L("Cleanup History"),
                       subtitle: L("Every item removed with CleanMac. Items still in the Trash can be put back with one click.")) {
                Button(L("Clear History")) { confirmClear = true }
                    .disabled(state.history.isEmpty)
            }
            Divider()
            if state.history.isEmpty {
                EmptyStateView(icon: "clock.arrow.circlepath", title: L("No cleanups yet"),
                               message: L("Items you delete or move to the Trash will be listed here."))
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
                    Text(L("\(state.history.count) records · \(trashed.reduce(Int64(0)) { $0 + $1.size }.formattedBytes) moved to the Trash"))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .confirmationDialog(L("Clear history?"), isPresented: $confirmClear) {
            Button(L("Clear History"), role: .destructive) { state.clearHistory() }
        } message: {
            Text(L("Only the records are deleted; files in the Trash aren’t touched."))
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
                    Text(L("Restored")).foregroundStyle(.green)
                } else if record.isPermanent {
                    Text(L("Deleted permanently")).foregroundStyle(.secondary)
                } else if inTrash {
                    Button(L("Restore")) { state.restore(record) }
                } else {
                    Text(L("Emptied from the Trash")).foregroundStyle(.secondary)
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
            PageHeader(title: L("Exclusions"),
                       subtitle: L("Folders and files here are never suggested by the assistant, never shown in lists, and never deleted by CleanMac.")) {
                Button {
                    state.chooseExclusion()
                } label: { Label(L("Add…"), systemImage: "plus") }
            }
            Divider()
            if state.excludedPaths.isEmpty {
                EmptyStateView(icon: "lock.shield", title: L("Nothing is excluded"),
                               message: L("Add your active projects, important archives, or any folder you don’t want touched. You can also right-click in a list and choose \"Exclude\"."),
                               actionTitle: L("Add Folder")) { state.chooseExclusion() }
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
                                Text(L("not found")).font(.caption).foregroundStyle(.orange)
                            }
                            Button { Finder.reveal([URL(fileURLWithPath: path)]) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.borderless)
                            Button(role: .destructive) { state.removeExclusion(path) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.borderless)
                                .help(L("Remove from list"))
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }
}
