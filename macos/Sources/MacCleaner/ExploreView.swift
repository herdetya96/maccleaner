import MacCleanerCore
import SwiftUI

struct NoResults: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "externaldrive.badge.questionmark").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("Belum ada hasil pemindaian").font(.title3.bold())
            Text("Pindai folder rumah atau seluruh disk terlebih dahulu.").foregroundStyle(.secondary)
            Button("Pindai folder rumah") { model.startScan(NSHomeDirectory()) }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ExploreView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        if !model.hasResults {
            NoResults()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                header
                Divider()
                HSplitView {
                    folderList.frame(minWidth: 460)
                    DetailPanel(entry: model.selectedEntry ?? model.folderSelf,
                                isCurrentFolder: model.selectedEntry == nil)
                        .frame(minWidth: 300, idealWidth: 340, maxWidth: 420)
                }
            }
        }
    }

    var header: some View {
        HStack {
            Button { model.goUp() } label: { Image(systemName: "chevron.up") }
                .disabled(model.crumbs.count < 2)
                .help("Naik satu folder")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(Array(model.crumbs.enumerated()), id: \.offset) { i, c in
                        if i > 0 { Text("/").foregroundStyle(.secondary) }
                        Button(c.name) { model.openFolder(c.path) }.buttonStyle(.link)
                    }
                }
            }
            Spacer()
            if let f = model.folderSelf {
                Text(Format.bytes(f.size)).font(.headline).monospacedDigit()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    var folderList: some View {
        let maxSize = max(1, model.folderItems.first?.size ?? 1)
        return List(model.folderItems, selection: Binding(
            get: { model.selectedEntry?.id },
            set: { id in model.selectedEntry = model.folderItems.first { $0.id == id } }
        )) { item in
            FolderRow(item: item, fraction: Double(item.size) / Double(maxSize))
                .tag(item.id)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let item = model.folderItems.first(where: { $0.id == id }), !item.isOther {
                if item.isDir { Button("Buka folder") { model.openFolder(item.path) } }
                Button("Tampilkan di Finder") { model.reveal(item.path) }
                if item.canTrash {
                    Divider()
                    Button(item.cleansContents ? "Kosongkan isinya…" : "Buang ke Sampah…") { model.askTrash([item]) }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first, let item = model.folderItems.first(where: { $0.id == id }), item.isDir, !item.isOther {
                model.openFolder(item.path)
            }
        }
        .overlay {
            if model.folderItems.isEmpty { Text("Folder ini kosong.").foregroundStyle(.secondary) }
        }
    }
}

struct FolderRow: View {
    let item: DiskItem
    let fraction: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.isOther ? "ellipsis" : item.isDir ? (item.denied ? "lock.fill" : "folder.fill") : "doc")
                .foregroundStyle(item.isDir ? Color.accentColor : Color.secondary)
                .frame(width: 18)
            HStack(spacing: 6) {
                Text(item.name).lineLimit(1).truncationMode(.middle)
                if item.isDir && item.files > 0 {
                    Text("\(Format.count(item.files)) file").font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            UsageBar(fraction: fraction).frame(width: 140)
            Text(Format.bytes(item.size)).monospacedDigit().fontWeight(.semibold)
                .frame(width: 80, alignment: .trailing)
            Group {
                if item.isOther { Color.clear } else { SafetyBadge(safety: item.info.safety) }
            }
            .frame(width: 120, alignment: .trailing)
        }
        .padding(.vertical, 3)
        .foregroundStyle(item.isOther ? Color.secondary : Color.primary)
    }
}

struct DetailPanel: View {
    @EnvironmentObject var model: AppModel
    let entry: DiskItem?
    let isCurrentFolder: Bool

    var body: some View {
        ScrollView {
            if let e = entry {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isCurrentFolder ? "Folder ini" : e.isDir ? "Folder" : "File")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(e.name).font(.title2.bold()).textSelection(.enabled)
                        Text(e.display).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    HStack {
                        Text(Format.bytes(e.size)).font(.system(size: 28, weight: .bold))
                        Spacer()
                        SafetyBadge(safety: e.info.safety)
                    }
                    Text(e.isDir ? "\(Format.count(e.files)) file · diubah \(Format.ago(e.mtime))"
                                 : "Diubah \(Format.ago(e.mtime))")
                        .font(.caption).foregroundStyle(.secondary)
                    if e.denied {
                        Note(text: "Isi folder tidak bisa dibaca (izin ditolak). Ukuran sebenarnya bisa lebih besar.",
                             color: .orange)
                    }
                    ExplanationView(info: e.info)
                    HStack {
                        if e.isDir && !isCurrentFolder {
                            Button("Buka folder") { model.openFolder(e.path) }.buttonStyle(.borderedProminent)
                        }
                        Button("Tampilkan di Finder") { model.reveal(e.path) }
                    }
                    action(e)
                }
                .padding(18)
            } else {
                Text("Pilih salah satu baris untuk melihat penjelasannya.")
                    .foregroundStyle(.secondary).padding(18)
            }
        }
    }

    @ViewBuilder
    func action(_ e: DiskItem) -> some View {
        if e.isProtected {
            Note(text: "Folder penting — dilindungi dari penghapusan oleh aplikasi ini.")
        } else if e.info.safety == .jangan {
            Note(text: "Jangan dihapus manual. \(e.info.how)", color: .red)
        } else if e.info.partOf {
            Note(text: "Ini bagian dalam dari \"\(e.info.title)\". Menghapus satu file di dalamnya bisa merusak keseluruhannya — buang seluruh foldernya saja.",
                 color: .orange)
        } else if !e.info.deletable {
            Note(text: "Bersihkan lewat caranya sendiri (lihat di atas), bukan dengan menghapus file.", color: .orange)
        } else {
            Button(role: .destructive) { model.askTrash([e]) } label: {
                Text(e.cleansContents ? "Kosongkan isinya" : "Buang ke Sampah").frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
    }
}
