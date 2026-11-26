import AppKit
import Foundation
import MacCleanerCore
import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, explore, recs, large
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return "Ringkasan"
        case .explore: return "Analisis Folder"
        case .recs: return "Rekomendasi"
        case .large: return "File Besar"
        }
    }
    var icon: String {
        switch self {
        case .overview: return "chart.pie"
        case .explore: return "folder"
        case .recs: return "checkmark.seal"
        case .large: return "doc.text.magnifyingglass"
        }
    }
}

/// Satu baris di daftar folder / file besar.
struct DiskItem: Identifiable, Hashable {
    let path: String
    let name: String
    let display: String
    let size: Int64
    let files: Int
    let isDir: Bool
    let mtime: TimeInterval
    let denied: Bool
    let info: RuleInfo
    let isProtected: Bool
    /// Baris gabungan "N file kecil lainnya".
    let isOther: Bool

    var id: String { isOther ? "other:" + path : path }
    var canTrash: Bool { !isOther && !isProtected && info.deletable && info.safety != .jangan }
    var cleansContents: Bool { isDir && info.mode == .contents }

    static func == (a: DiskItem, b: DiskItem) -> Bool { a.id == b.id && a.size == b.size }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Item yang akan dibuang (untuk dialog konfirmasi).
struct TrashItem: Identifiable, Hashable {
    let path: String
    let display: String
    let size: Int64
    let safety: Safety
    let contents: Bool
    var id: String { path }
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let isError: Bool
}

final class AppModel: ObservableObject {
    @Published var section: Page = .overview
    @Published var disks: [DiskInfo] = []
    @Published var scanning = false
    @Published var progress = ScanProgress()
    @Published var scanRootDisplay = ""
    @Published var scanElapsed: TimeInterval = 0
    @Published var scanEta: TimeInterval?
    @Published private(set) var scan: Scan?
    @Published var summary: Summary?
    @Published var groups: [RecGroup] = []
    @Published var trashSize: Int64 = 0
    @Published var large: [DiskItem] = []
    @Published var folderPath: String?
    @Published var folderItems: [DiskItem] = []
    @Published var folderSelf: DiskItem?
    @Published var crumbs: [(name: String, path: String)] = []
    @Published var selectedEntry: DiskItem?
    @Published var picked: Set<String> = []          // pilihan di Rekomendasi
    @Published var pendingTrash: [TrashItem]? = nil   // dialog konfirmasi
    @Published var confirmEmptyTrash = false
    @Published var toast: Toast?
    @Published var needsFullDiskAccess = false

    let matcher = RuleMatcher(home: NSHomeDirectory())
    private var timer: Timer?

    var hasResults: Bool { scan?.root != nil && !scanning }

    init() {
        refreshDisks()
        needsFullDiskAccess = !Self.hasFullDiskAccess()
    }

    // MARK: Disk

    func refreshDisks() {
        disks = Disks.list()
    }

    static func hasFullDiskAccess() -> Bool {
        // Folder ini hanya bisa dibaca bila aplikasi punya Akses Disk Penuh.
        let probe = NSHomeDirectory() + "/Library/Safari"
        guard FileManager.default.fileExists(atPath: probe) else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: Pindai

    func startScan(_ path: String) {
        scan?.cancel()
        let s = Scan(path: path, matcher: matcher)
        scan = s
        scanning = true
        progress = ScanProgress()
        scanRootDisplay = matcher.display(s.rootPath)
        picked.removeAll()
        selectedEntry = nil
        scanEta = nil
        // Perkiraan total dari riwayat pemindaian sebelumnya atau pemakaian disk.
        ScanHistory.prepare(s, disks: disks)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            s.run()
            ScanHistory.remember(s)
            DispatchQueue.main.async { self?.scanFinished(s) }
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self = self, let cur = self.scan, cur === s else { return }
            let p = s.progress
            self.progress = p
            self.scanElapsed = p.elapsed
            // Haluskan sisa waktu agar angkanya tidak melompat-lompat.
            if let new = p.eta {
                self.scanEta = self.scanEta.map { $0 * 0.8 + new * 0.2 } ?? new
            } else {
                self.scanEta = nil
            }
        }
    }

    func chooseFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Pindai"
        panel.message = "Pilih folder yang ingin dipindai"
        if panel.runModal() == .OK, let url = panel.url {
            startScan(url.path)
        }
    }

    func cancelScan() {
        scan?.cancel()
    }

    private func scanFinished(_ s: Scan) {
        guard s === scan else { return }
        timer?.invalidate()
        timer = nil
        scanning = false
        switch s.state {
        case .failed(let msg):
            show("Pemindaian gagal: \(msg)", error: true)
            return
        case .cancelled:
            show("Pemindaian dibatalkan — hasil sebagian ditampilkan.")
        default:
            break
        }
        folderPath = s.rootPath
        reloadAll()
        if section == .overview && summary == nil { section = .overview }
    }

    // MARK: Muat ulang hasil

    func reloadAll() {
        guard let s = scan, s.root != nil else { return }
        refreshDisks()
        summary = s.summary(disk: Disks.disk(for: s.rootPath, in: disks))
        groups = s.recommendations()
        trashSize = TrashService.size()
        large = s.largestFiles(limit: 150).map { f in
            let info = s.fileRule(f.path, parent: s.parentNode(of: f.path))
            return DiskItem(path: f.path, name: f.name, display: matcher.display(f.path), size: f.size,
                         files: 1, isDir: false, mtime: f.mtime, denied: false, info: info,
                         isProtected: matcher.isProtected(f.path), isOther: false)
        }
        picked = picked.filter { p in groups.contains { g in g.items.contains { $0.path == p } } }
        openFolder(folderPath ?? s.rootPath)
    }

    func openFolder(_ path: String) {
        guard let s = scan else { return }
        guard let n = s.index[path] ?? s.root else { return }
        folderPath = n.path
        var items: [DiskItem] = n.children.prefix(300).map { entry(for: $0) }
        var listed: Int64 = 0
        for f in n.top {
            let info = s.fileRule(f.path, parent: n)
            items.append(DiskItem(path: f.path, name: f.name, display: matcher.display(f.path), size: f.size,
                               files: 1, isDir: false, mtime: f.mtime, denied: false, info: info,
                               isProtected: matcher.isProtected(f.path), isOther: false))
            listed += f.size
        }
        let hidden = n.children.dropFirst(300)
        let other = n.own - listed + hidden.reduce(0) { $0 + $1.size }
        let otherCount = n.files - n.children.prefix(300).reduce(0) { $0 + $1.files } - n.top.count
        if other > 0 && otherCount > 0 {
            items.append(DiskItem(path: n.path, name: "\(Format.count(otherCount)) file kecil lainnya",
                               display: "", size: other, files: otherCount, isDir: false, mtime: 0,
                               denied: false, info: RuleInfo(rule: n.rule, inherited: true, depth: n.depth + 1),
                               isProtected: true, isOther: true))
        }
        folderItems = items.sorted { $0.size > $1.size }
        folderSelf = entry(for: n)
        var c: [(String, String)] = []
        var p: Node? = n
        while let cur = p {
            c.append((cur.parent == nil ? matcher.display(cur.path) : cur.name, cur.path))
            p = cur.parent
        }
        crumbs = c.reversed().map { (name: $0.0, path: $0.1) }
        if let sel = selectedEntry, !folderItems.contains(where: { $0.id == sel.id }) {
            selectedEntry = nil
        }
    }

    func goUp() {
        if crumbs.count > 1 { openFolder(crumbs[crumbs.count - 2].path) }
    }

    private func entry(for n: Node) -> DiskItem {
        DiskItem(path: n.path, name: n.name, display: matcher.display(n.path), size: n.size, files: n.files,
              isDir: true, mtime: n.mtime, denied: n.denied, info: n.info,
              isProtected: matcher.isProtected(n.path), isOther: false)
    }

    func showInExplore(_ path: String) {
        guard let s = scan else { return }
        var p = path
        while s.index[p] == nil && p != "/" { p = (p as NSString).deletingLastPathComponent }
        openFolder(p)
        selectedEntry = folderItems.first { $0.path == path }
        section = .explore
    }

    // MARK: Pilihan rekomendasi

    var pickedItems: [TrashItem] {
        var out: [TrashItem] = []
        for g in groups where g.kind == .trash {
            for it in g.items where picked.contains(it.path) {
                out.append(TrashItem(path: it.path, display: it.display, size: it.size,
                                     safety: g.rule.safety, contents: false))
            }
        }
        return out
    }

    var pickedTotal: Int64 { pickedItems.reduce(0) { $0 + $1.size } }

    func pickAllSafe() {
        for g in groups where g.kind == .trash && g.rule.safety == .aman {
            for it in g.items { picked.insert(it.path) }
        }
    }

    func setGroup(_ g: RecGroup, picked on: Bool) {
        for it in g.items {
            if on { picked.insert(it.path) } else { picked.remove(it.path) }
        }
    }

    // MARK: Buang

    func askTrash(_ entries: [DiskItem]) {
        let items = entries.filter(\.canTrash).map {
            TrashItem(path: $0.path, display: $0.display, size: $0.size, safety: $0.info.safety,
                      contents: $0.cleansContents)
        }
        if items.isEmpty {
            show("Item yang dipilih tidak bisa dibuang dari aplikasi (lihat penjelasannya).", error: true)
        } else {
            pendingTrash = items
        }
    }

    func performTrash(_ items: [TrashItem]) {
        pendingTrash = nil
        guard let s = scan else { return }
        let cleaner = Cleaner(scan: s)
        let reqs = items.map { Cleaner.Request(path: $0.path, contents: $0.contents) }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let res = cleaner.trash(reqs)
            DispatchQueue.main.async {
                guard let self = self else { return }
                for i in items { self.picked.remove(i.path) }
                if !res.done.isEmpty {
                    self.show("\(res.done.count) item dipindah ke Sampah (\(Format.bytes(res.freed))). "
                              + "Ruang disk baru benar-benar kosong setelah Sampah dikosongkan.")
                }
                if !res.errors.isEmpty {
                    let detail = res.errors.prefix(3)
                        .map { "\(self.matcher.display($0.path)): \($0.message)" }
                        .joined(separator: "\n")
                    self.show("\(res.errors.count) item gagal:\n\(detail)", error: true)
                }
                self.reloadAll()
            }
        }
    }

    func emptyTrash() {
        confirmEmptyTrash = false
        DispatchQueue.global().async { [weak self] in
            let r = TrashService.empty()
            DispatchQueue.main.async {
                self?.show(r.message, error: !r.ok)
                self?.trashSize = TrashService.size()
                self?.refreshDisks()
            }
        }
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        show("Perintah disalin.")
    }

    func show(_ text: String, error: Bool = false) {
        let t = Toast(text: text, isError: error)
        toast = t
        DispatchQueue.main.asyncAfter(deadline: .now() + (error ? 9 : 5)) { [weak self] in
            if self?.toast == t { self?.toast = nil }
        }
    }
}
