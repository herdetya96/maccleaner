import Foundation

public enum RecKind: String, Sendable {
    /// Bisa dibuang langsung dari aplikasi.
    case trash
    /// Harus dibersihkan lewat aplikasi/perintah terkait.
    case manual
}

public struct RecItem: Identifiable, Hashable, Sendable {
    public let path: String
    public let display: String
    public let size: Int64
    public let files: Int
    public let mtime: TimeInterval
    public let isDir: Bool
    public var id: String { path }
}

public struct RecGroup: Identifiable, Sendable {
    public let rule: Rule
    public let kind: RecKind
    public var total: Int64
    public var items: [RecItem]
    public var id: String { rule.id + ":" + kind.rawValue }
}

public struct Insight: Identifiable, Sendable {
    public enum Level: String, Sendable { case aman, hati, info, sedang, tinggi, kritis }
    public let level: Level
    public let text: String
    public var id: String { text }
}

public struct CategoryTotal: Identifiable, Sendable {
    public let id: String
    public let label: String
    public let size: Int64
}

public struct Summary: Sendable {
    public let display: String
    public let scanned: Int64
    public let files: Int
    public let elapsed: TimeInterval
    public let categories: [CategoryTotal]
    public let wholeDisk: Bool
    public let unscanned: Int64
    public let safeTotal: Int64
    public let cautionTotal: Int64
    public let denied: Int
    public let insights: [Insight]
}

public extension Scan {
    /// Kandidat pembersihan, dikelompokkan per aturan.
    func recommendations(minSize: Int64 = 100 * 1024) -> [RecGroup] {
        var out: [(Rule, RecKind, RecItem)] = []
        var covered: [String] = []
        let m = matcher

        func item(_ n: Node) -> RecItem {
            RecItem(path: n.path, display: m.display(n.path), size: n.size, files: n.files,
                    mtime: n.mtime, isDir: true)
        }
        func add(_ n: Node, _ r: Rule, _ k: RecKind) {
            out.append((r, k, item(n)))
            covered.append(n.path)
        }
        func visit(_ n: Node) {
            let own = n.rule != nil && !n.inherited
            if own, let r = n.rule, r.deletable, r.safety == .aman || r.safety == .hati {
                if r.mode == .contents {
                    for c in n.children {
                        if c.inherited && c.rule === r {
                            if c.size >= minSize { add(c, r, .trash) }
                        } else {
                            visit(c)
                        }
                    }
                    return
                }
                if n.size >= minSize { add(n, r, .trash) }
                return
            }
            if own, let r = n.rule, !r.deletable, [.aman, .hati, .periksa].contains(r.safety),
               !(r.how.isEmpty && r.command.isEmpty), n.size >= 50_000_000,
               !["user-library", "home", "users", "system-library"].contains(r.id) {
                add(n, r, .manual)
                return
            }
            for c in n.children { visit(c) }
        }
        if let root = root { visit(root) }

        // File besar yang dikenali (installer, file update iOS, ...).
        for f in topFiles {
            if covered.contains(where: { f.path.hasPrefix($0 + "/") }) { continue }
            let info = fileRule(f.path, parent: parentNode(of: f.path))
            guard let r = info.rule, !info.inherited, r.deletable else { continue }
            guard r.safety == .aman || r.safety == .hati || r.category == "installer" else { continue }
            out.append((r, .trash, RecItem(path: f.path, display: m.display(f.path), size: f.size,
                                           files: 1, mtime: f.mtime, isDir: false)))
        }
        // File besar di Unduhan yang tidak diubah > 90 hari.
        let downloads = m.home + "/Downloads/"
        let limit = Date().timeIntervalSince1970 - 90 * 86_400
        let known = Set(out.map { $0.2.path })
        for f in topFiles where f.path.hasPrefix(downloads) && !known.contains(f.path)
            && f.mtime <= limit && f.size >= 20_000_000 {
            out.append((Rule.oldDownloads, .trash, RecItem(path: f.path, display: m.display(f.path),
                                                          size: f.size, files: 1, mtime: f.mtime,
                                                          isDir: false)))
        }

        var groups: [String: RecGroup] = [:]
        var order: [String] = []
        for (rule, kind, it) in out {
            let key = rule.id + ":" + kind.rawValue
            if groups[key] == nil {
                groups[key] = RecGroup(rule: rule, kind: kind, total: 0, items: [])
                order.append(key)
            }
            groups[key]!.total += it.size
            groups[key]!.items.append(it)
        }
        var result = order.compactMap { groups[$0] }.filter { $0.rule.id != "trash" }
        for i in result.indices { result[i].items.sort { $0.size > $1.size } }
        result.sort {
            if ($0.kind == .trash) != ($1.kind == .trash) { return $0.kind == .trash }
            if $0.rule.safety.order != $1.rule.safety.order { return $0.rule.safety.order < $1.rule.safety.order }
            return $0.total > $1.total
        }
        return result
    }

    /// Ringkasan "kenapa penuh" + temuan.
    func summary(disk: DiskInfo?) -> Summary {
        let totals = categoryTotals()
        let cats = totals.filter { $0.value > 0 }
            .map { CategoryTotal(id: $0.key, label: Categories.label($0.key), size: $0.value) }
            .sorted { $0.size > $1.size }
        let scanned = root?.size ?? 0
        let wholeDisk = disk.map { rootPath == $0.mount } ?? false
        let unscanned = disk.map { max(0, $0.used - scanned) } ?? 0
        let recs = recommendations()
        let safeTotal = recs.filter { $0.rule.safety == .aman && $0.kind == .trash }.reduce(0) { $0 + $1.total }
        let cautionTotal = recs.filter { $0.rule.safety == .hati }.reduce(0) { $0 + $1.total }
        let gb: Int64 = 1_000_000_000
        let where_ = matcher.display(rootPath)

        var ins: [Insight] = []
        if let d = disk {
            ins.append(Insight(level: Insight.Level(rawValue: d.level.rawValue) ?? .info,
                               text: "\(d.name) terpakai \(Int(d.percent.rounded()))% (\(Format.bytes(d.used)) dari \(Format.bytes(d.total))). \(d.level.message)"))
        }
        if !cats.isEmpty {
            let top = cats.prefix(3).map { "\($0.label) (\(Format.bytes($0.size)))" }.joined(separator: ", ")
            ins.append(Insight(level: .info, text: "Pemakai ruang terbesar di \(where_): \(top)."))
        }
        if safeTotal > 0 {
            ins.append(Insight(level: .aman, text: "Sekitar \(Format.bytes(safeTotal)) bisa dikosongkan dengan aman (cache, build, installer, dll)."))
        }
        for g in recs.filter({ $0.kind == .trash }).prefix(3) where g.total >= 500_000_000 {
            ins.append(Insight(level: g.rule.safety == .aman ? .aman : .hati,
                               text: "\(g.rule.title): \(Format.bytes(g.total)) di \(g.items.count) lokasi — \(g.rule.safety.label.lowercased())"))
        }
        if cautionTotal >= gb {
            ins.append(Insight(level: .hati, text: "\(Format.bytes(cautionTotal)) lainnya bisa dikosongkan tapi perlu dipertimbangkan (backup, simulator, VM, dll)."))
        }
        if disk != nil && wholeDisk && unscanned >= 2 * gb {
            ins.append(Insight(level: .info, text: "\(Format.bytes(unscanned)) tidak terlihat oleh pemindaian: biasanya data sistem macOS, snapshot Time Machine lokal, swap, atau folder yang aksesnya ditolak."))
        } else if disk != nil && !wholeDisk && unscanned >= 5 * gb {
            ins.append(Insight(level: .info, text: "\(Format.bytes(unscanned)) lainnya berada di luar \(where_) (aplikasi, sistem, pengguna lain). Pindai \"Seluruh disk\" untuk melihat semuanya."))
        }
        if deniedCount > 0 {
            ins.append(Insight(level: .hati, text: "\(deniedCount) folder tidak bisa dibaca karena izin. Beri \"Akses Disk Penuh\" ke MacCleaner: Pengaturan Sistem → Privasi & Keamanan → Akses Disk Penuh."))
        }
        return Summary(display: where_, scanned: scanned, files: root?.files ?? 0, elapsed: elapsed,
                       categories: cats, wholeDisk: wholeDisk, unscanned: unscanned,
                       safeTotal: safeTotal, cautionTotal: cautionTotal, denied: deniedCount,
                       insights: ins)
    }
}
