import MacCleanerCore
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ringkasan Disk").font(.largeTitle.bold())
                        Text("Lihat disk mana yang penuh, lalu pindai untuk tahu penyebabnya.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { model.refreshDisks() } label: { Label("Muat ulang", systemImage: "arrow.clockwise") }
                    Button { model.chooseFolderAndScan() } label: { Label("Pindai folder lain…", systemImage: "folder.badge.gearshape") }
                }

                if model.needsFullDiskAccess {
                    HStack {
                        Image(systemName: "lock.shield").foregroundStyle(.orange)
                        Text("MacCleaner belum punya Akses Disk Penuh, jadi sebagian folder (Mail, Pesan, Safari) tidak bisa dihitung.")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("Buka Pengaturan") { model.openFullDiskAccessSettings() }
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 16)], spacing: 16) {
                    ForEach(model.disks) { DiskCard(disk: $0) }
                }

                if let s = model.summary {
                    HStack(alignment: .top, spacing: 16) {
                        WhyFullCard(summary: s)
                        FindingsCard(summary: s)
                    }
                }
            }
            .padding(24)
        }
    }
}

struct DiskCard: View {
    @EnvironmentObject var model: AppModel
    let disk: DiskInfo

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading) {
                    Text(disk.name).font(.headline)
                    Text(disk.mount + (disk.format.isEmpty ? "" : " · " + disk.format))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(disk.percent.rounded()))%")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(disk.level == .aman || disk.level == .sedang ? Color.primary : disk.level.color)
            }
            UsageBar(fraction: disk.percent / 100, color: disk.level.color, height: 12)
            HStack {
                Text("Terpakai \(Format.bytes(disk.used))")
                Spacer()
                Text("Tersedia \(Format.bytes(disk.available)) dari \(Format.bytes(disk.total))")
            }
            .font(.caption).foregroundStyle(.secondary)
            if disk.purgeable > 1_000_000_000 {
                Text("Termasuk \(Format.bytes(disk.purgeable)) yang bisa dibersihkan macOS sendiri (purgeable).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Note(text: disk.level.message,
                 color: disk.level == .tinggi || disk.level == .kritis ? disk.level.color : .secondary)
            HStack {
                if disk.isRoot {
                    Button("Pindai folder rumah") { model.startScan(NSHomeDirectory()) }
                        .buttonStyle(.borderedProminent)
                    Button("Pindai seluruh disk") { model.startScan("/") }
                } else {
                    Button("Pindai volume ini") { model.startScan(disk.mount) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}

struct WhyFullCard: View {
    let summary: Summary

    var slices: [DonutSlice] {
        var all = summary.categories.map { DonutSlice(id: $0.id, label: $0.label, size: $0.size) }
        if summary.wholeDisk && summary.unscanned > 0 {
            all.append(DonutSlice(id: "unscanned", label: "Data sistem / tak terbaca", size: summary.unscanned))
        }
        let total = max(1, all.reduce(0) { $0 + $1.size })
        var shown: [DonutSlice] = []
        var rest: Int64 = 0
        for (i, s) in all.enumerated() {
            if i < 9 && Double(s.size) / Double(total) > 0.004 { shown.append(s) } else { rest += s.size }
        }
        if rest > 0 { shown.append(DonutSlice(id: "other", label: "Lainnya (kecil)", size: rest)) }
        return shown
    }

    var body: some View {
        let sl = slices
        let total = max(1, sl.reduce(0) { $0 + $1.size })
        Card {
            Text("Kenapa penuh?").font(.title3.bold())
            Text("\(summary.display) · \(Format.bytes(summary.scanned)) dalam \(Format.count(summary.files)) file · selesai dalam \(Format.duration(summary.elapsed))")
                .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .center, spacing: 18) {
                Donut(slices: sl).frame(width: 210, height: 210)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(sl) { s in
                        HStack {
                            RoundedRectangle(cornerRadius: 3).fill(CategoryColor.of(s.id)).frame(width: 12, height: 12)
                            Text(s.label)
                            Spacer()
                            Text("\(Format.bytes(s.size)) · \(Int((Double(s.size) / Double(total) * 100).rounded()))%")
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
    }
}

struct FindingsCard: View {
    @EnvironmentObject var model: AppModel
    let summary: Summary

    var body: some View {
        Card {
            Text("Temuan").font(.title3.bold())
            ForEach(summary.insights) { ins in
                HStack(spacing: 10) {
                    Rectangle().fill(ins.level.color).frame(width: 3)
                    Text(ins.text).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6).padding(.trailing, 8)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack(spacing: 28) {
                VStack(alignment: .leading) {
                    Text(Format.bytes(summary.safeTotal)).font(.title2.bold()).foregroundStyle(.green)
                    Text("aman dikosongkan").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading) {
                    Text(Format.bytes(summary.cautionTotal)).font(.title2.bold()).foregroundStyle(.orange)
                    Text("perlu dipertimbangkan").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.top, 4)
            HStack {
                Button("Lihat rekomendasi →") { model.section = .recs }.buttonStyle(.borderedProminent)
                Button("Telusuri folder") { model.section = .explore }
            }
        }
    }
}
