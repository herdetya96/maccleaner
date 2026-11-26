import MacCleanerCore
import SwiftUI

struct LargeFilesView: View {
    @EnvironmentObject var model: AppModel
    @State private var selection = Set<String>()
    @State private var sortOrder = [KeyPathComparator(\DiskItem.size, order: .reverse)]

    var rows: [DiskItem] { model.large.sorted(using: sortOrder) }

    var body: some View {
        if !model.hasResults {
            NoResults()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("File Terbesar").font(.largeTitle.bold())
                        Text("File tunggal terbesar di area yang dipindai. Pilih beberapa dengan ⌘-klik.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(24)

                Table(rows, selection: $selection, sortOrder: $sortOrder) {
                    TableColumn("Nama", value: \.name) { e in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.name).fontWeight(.medium)
                            Text(e.display).font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        }
                    }
                    .width(min: 260, ideal: 420)
                    TableColumn("Ukuran", value: \.size) { e in
                        Text(Format.bytes(e.size)).monospacedDigit()
                    }
                    .width(90)
                    TableColumn("Diubah", value: \.mtime) { e in
                        Text(Format.ago(e.mtime)).foregroundStyle(.secondary)
                    }
                    .width(130)
                    TableColumn("Status") { e in
                        VStack(alignment: .leading, spacing: 1) {
                            SafetyBadge(safety: e.info.safety)
                            Text(e.info.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .help(e.info.why)
                    }
                    .width(min: 150, ideal: 180)
                }
                .contextMenu(forSelectionType: String.self) { ids in
                    let items = model.large.filter { ids.contains($0.id) }
                    if items.count == 1, let e = items.first {
                        Button("Tampilkan di Finder") { model.reveal(e.path) }
                        Button("Lihat di Analisis Folder") { model.showInExplore(e.path) }
                    }
                    if items.contains(where: \.canTrash) {
                        Divider()
                        Button("Buang ke Sampah…") { model.askTrash(items) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first { model.reveal(id) }
                }

                HStack {
                    let chosen = model.large.filter { selection.contains($0.id) }
                    let can = chosen.filter(\.canTrash)
                    Text(chosen.isEmpty ? "Pilih file untuk melihat opsi."
                         : "\(chosen.count) dipilih · \(Format.bytes(can.reduce(0) { $0 + $1.size })) bisa dibuang"
                           + (can.count < chosen.count ? " (\(chosen.count - can.count) dilindungi)" : ""))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Tampilkan di Finder") { chosen.forEach { model.reveal($0.path) } }
                        .disabled(chosen.isEmpty)
                    Button("Buang ke Sampah…") { model.askTrash(can) }
                        .buttonStyle(.borderedProminent).tint(.red)
                        .disabled(can.isEmpty)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                .background(.bar)
            }
            .onChange(of: model.large) { _ in
                selection = selection.filter { id in model.large.contains { $0.id == id } }
            }
        }
    }
}
