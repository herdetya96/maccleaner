import MacCleanerCore
import SwiftUI

struct RecommendationsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if !model.hasResults {
            NoResults()
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rekomendasi Pembersihan").font(.largeTitle.bold())
                                Text("Dikelompokkan berdasarkan jenis. File dipindah ke Sampah dulu, jadi masih bisa dikembalikan.")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Pilih semua yang aman") { model.pickAllSafe() }
                        }
                        if model.trashSize > 0 { trashCard }
                        let trashable = model.groups.filter { $0.kind == .trash }
                        let manual = model.groups.filter { $0.kind == .manual }
                        if model.groups.isEmpty {
                            Card { Text("Tidak ada yang perlu dibersihkan di area ini. 🎉").frame(maxWidth: .infinity) }
                        }
                        if !trashable.isEmpty {
                            Text("Bisa dibuang dari sini").font(.title3.bold()).padding(.top, 6)
                            ForEach(trashable) { GroupCard(group: $0) }
                        }
                        if !manual.isEmpty {
                            Text("Perlu dibersihkan dari aplikasinya").font(.title3.bold()).padding(.top, 14)
                            Text("Item ini besar, tapi menghapus filenya langsung bisa merusak data. Ikuti cara yang disarankan.")
                                .font(.callout).foregroundStyle(.secondary)
                            ForEach(manual) { GroupCard(group: $0) }
                        }
                    }
                    .padding(24)
                }
                if !model.picked.isEmpty { selectionBar }
            }
        }
    }

    var trashCard: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: "trash.fill").font(.title).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sampah berisi \(Format.bytes(model.trashSize))").font(.headline)
                    Text("File di Sampah masih memakan ruang disk sampai dikosongkan. Mengosongkan Sampah bersifat permanen.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Kosongkan Sampah…") { model.confirmEmptyTrash = true }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }
    }

    var selectionBar: some View {
        HStack {
            Text("\(model.picked.count) item dipilih · \(Format.bytes(model.pickedTotal))").font(.headline)
            Spacer()
            Button("Batal pilih") { model.picked.removeAll() }
            Button("Buang ke Sampah…") { model.pendingTrash = model.pickedItems }
                .buttonStyle(.borderedProminent).tint(.red)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

struct GroupCard: View {
    @EnvironmentObject var model: AppModel
    let group: RecGroup
    @State private var open = false

    var selectable: Bool { group.kind == .trash }

    var groupState: Bool? {
        let n = group.items.filter { model.picked.contains($0.path) }.count
        if n == 0 { return false }
        return n == group.items.count ? true : nil
    }

    var body: some View {
        let r = group.rule
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if selectable {
                    Toggle("", isOn: Binding(
                        get: { groupState ?? false },
                        set: { model.setGroup(group, picked: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(r.title).font(.headline)
                        SafetyBadge(safety: r.safety)
                        if groupState == nil {
                            Text("sebagian dipilih").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(r.why).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(Format.bytes(group.total)).font(.headline).monospacedDigit()
                    Text("\(group.items.count) lokasi").font(.caption).foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { open.toggle() } }

            if open {
                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .top, spacing: 16) {
                        if !r.effect.isEmpty { Labeled(title: "Kalau dihapus", text: r.effect) }
                        if !r.how.isEmpty { Labeled(title: "Cara yang benar", text: r.how) }
                    }
                    if !r.command.isEmpty { CommandBox(command: r.command) }
                    ForEach(group.items.prefix(300)) { it in
                        HStack(spacing: 10) {
                            if selectable {
                                Toggle("", isOn: Binding(
                                    get: { model.picked.contains(it.path) },
                                    set: { on in
                                        if on { model.picked.insert(it.path) } else { model.picked.remove(it.path) }
                                    }
                                ))
                                .toggleStyle(.checkbox).labelsHidden()
                            }
                            Text(it.display).lineLimit(1).truncationMode(.head)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(Format.ago(it.mtime)).font(.caption).foregroundStyle(.secondary)
                            Text(Format.bytes(it.size)).monospacedDigit().frame(width: 80, alignment: .trailing)
                            Button { model.reveal(it.path) } label: { Image(systemName: "arrow.up.forward.square") }
                                .buttonStyle(.plain).help("Tampilkan di Finder")
                            Button { model.showInExplore(it.path) } label: { Image(systemName: "magnifyingglass") }
                                .buttonStyle(.plain).help("Lihat di Analisis Folder")
                        }
                        .font(.callout)
                    }
                    if group.items.count > 300 {
                        Text("…dan \(group.items.count - 300) lainnya").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(Color.primary.opacity(0.03))
            }
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
