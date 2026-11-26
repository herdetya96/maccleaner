import AppKit
import Foundation
import MacCleanerCore

/// Menjawab panggilan API dari antarmuka coss ui (React) di dalam WKWebView.
///
/// Bentuk JSON-nya sama persis dengan server Python (maccleaner/server.py),
/// sehingga antarmuka yang sama bisa diuji di browser lewat server Python.
final class ApiBridge {
    struct Failure: Error { let message: String }

    let matcher = RuleMatcher(home: NSHomeDirectory())
    private(set) var scan: Scan?
    private var disksCache: [DiskInfo] = []

    var home: String { matcher.home }

    // MARK: - Routing

    /// Dipanggil di antrean latar (kecuali rute yang butuh thread utama, lihat `needsMainThread`).
    func handle(method: String, path rawPath: String, body: [String: Any]) throws -> Any {
        let comps = URLComponents(string: "maccleaner://app" + rawPath)
        let path = comps?.path ?? rawPath
        let query = Dictionary(uniqueKeysWithValues: (comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        switch (method, path) {
        case ("GET", "/api/info"): return info()
        case ("GET", "/api/disks"): return ["disks": disks().map(diskJSON)]
        case ("GET", "/api/status"): return status()
        case ("POST", "/api/scan"): return try startScan(body["path"] as? String ?? home)
        case ("POST", "/api/cancel"):
            scan?.cancel()
            return ["ok": true]
        case ("GET", "/api/node"): return try node(query["path"])
        case ("GET", "/api/summary"): return try summary()
        case ("GET", "/api/recommendations"): return try recommendations()
        case ("GET", "/api/largefiles"): return try largeFiles()
        case ("POST", "/api/trash"): return try trash(body["items"] as? [[String: Any]] ?? [])
        case ("POST", "/api/empty-trash"):
            let r = TrashService.empty()
            return ["ok": r.ok, "message": r.message]
        case ("GET", "/api/ping"): return ["ok": true]
        default:
            throw Failure(message: "Tidak ditemukan: \(method) \(path)")
        }
    }

    /// Rute yang menyentuh AppKit dijalankan di thread utama.
    static let mainThreadRoutes: Set<String> = ["/api/choose-folder", "/api/reveal", "/api/open-fda", "/api/copy"]

    func handleOnMain(path: String, body: [String: Any]) -> Any {
        switch path {
        case "/api/choose-folder":
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.prompt = "Pindai"
            panel.message = "Pilih folder yang ingin dipindai"
            let path: Any = panel.runModal() == .OK ? (panel.url?.path ?? NSNull()) : NSNull()
            return ["path": path]
        case "/api/reveal":
            let p = body["path"] as? String ?? ""
            guard FileManager.default.fileExists(atPath: p) else { return ["ok": false] }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
            return ["ok": true]
        case "/api/open-fda":
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
            return ["ok": true]
        case "/api/copy":
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(body["text"] as? String ?? "", forType: .string)
            return ["ok": true]
        default:
            return ["__error": "Tidak ditemukan: \(path)"]
        }
    }

    // MARK: - Info & disk

    static func hasFullDiskAccess() -> Bool {
        // Folder ini hanya bisa dibaca bila aplikasi punya Akses Disk Penuh.
        let probe = NSHomeDirectory() + "/Library/Safari"
        guard FileManager.default.fileExists(atPath: probe) else { return true }
        return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
    }

    private func info() -> [String: Any] {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return [
            "version": version, "home": home, "platform": "darwin", "status": status(),
            "desktop": true, "needsFullDiskAccess": !ApiBridge.hasFullDiskAccess(),
        ]
    }

    private func disks() -> [DiskInfo] {
        disksCache = Disks.list()
        return disksCache
    }

    private func diskJSON(_ d: DiskInfo) -> [String: Any] {
        var scanPaths: [[String: String]] = []
        if d.isRoot {
            scanPaths.append(["label": "Folder rumah (\((home as NSString).lastPathComponent))", "path": home])
            scanPaths.append(["label": "Seluruh disk", "path": "/"])
        } else {
            scanPaths.append(["label": "Seluruh volume", "path": d.mount])
        }
        return [
            "name": d.name, "mount": d.mount, "total": d.total, "used": d.used, "free": d.free,
            "available": d.available, "purgeable": d.purgeable,
            "percent": (d.percent * 10).rounded() / 10, "level": d.level.rawValue, "message": d.level.message,
            "fs": d.format, "isRoot": d.isRoot, "scanPaths": scanPaths,
        ]
    }

    // MARK: - Pindai

    private func startScan(_ raw: String) throws -> [String: Any] {
        let path = ((raw as NSString).expandingTildeInPath as NSString).standardizingPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            throw Failure(message: "Folder tidak ditemukan: \(path)")
        }
        scan?.cancel()
        let s = Scan(path: path, matcher: matcher)
        ScanHistory.prepare(s, disks: disksCache.isEmpty ? disks() : disksCache)
        scan = s
        DispatchQueue.global(qos: .userInitiated).async {
            s.run()
            ScanHistory.remember(s)
        }
        return status()
    }

    private func stateName(_ s: Scan.State) -> String {
        switch s {
        case .idle: return "idle"
        case .running: return "running"
        case .done: return "done"
        case .cancelled: return "cancelled"
        case .failed: return "error"
        }
    }

    private func status() -> [String: Any] {
        guard let s = scan else {
            return ["state": "idle", "files": 0, "dirs": 0, "bytes": 0, "current": "", "elapsed": 0,
                    "denied": 0, "fraction": 0, "eta": NSNull(), "estimate": "tree"]
        }
        let p = s.progress
        var error = ""
        if case .failed(let msg) = s.state { error = msg }
        // Sebelum thread pemindai sempat mulai, anggap sudah "running".
        let state = s.state == .idle ? "running" : stateName(s.state)
        return [
            "state": state, "error": error, "root": s.rootPath, "display": matcher.display(s.rootPath),
            "files": p.files, "dirs": p.dirs, "bytes": p.bytes,
            "current": p.current.isEmpty ? "" : matcher.display(p.current),
            "elapsed": (s.elapsed * 10).rounded() / 10, "denied": s.deniedCount,
            "fraction": (p.fraction * 10000).rounded() / 10000, "eta": p.eta.map { $0 as Any } ?? NSNull(),
            "estimate": p.estimate.rawValue,
        ]
    }

    private func requireScan() throws -> Scan {
        guard let s = scan, s.root != nil, s.state != .running, s.state != .idle else {
            throw Failure(message: "Belum ada hasil pemindaian. Mulai pindai dulu.")
        }
        return s
    }

    // MARK: - Hasil

    private func ruleJSON(_ info: RuleInfo) -> [String: Any] {
        var d: [String: Any] = [
            "id": info.rule?.id ?? NSNull(), "title": info.title, "category": info.category,
            "categoryLabel": Categories.label(info.category), "safety": info.safety.rawValue,
            "safetyLabel": info.safety.label, "why": info.why, "effect": info.effect, "how": info.how,
            "command": info.command, "mode": info.mode == .contents ? "contents" : "self",
            "deletable": info.deletable, "inherited": info.inherited,
        ]
        if info.partOf { d["partOf"] = true }
        return d
    }

    private func itemJSON(path: String, name: String, size: Int64, files: Int, isDir: Bool, mtime: TimeInterval,
                          info: RuleInfo, parentSize: Int64, denied: Bool = false) -> [String: Any] {
        [
            "name": name, "path": path, "display": matcher.display(path), "size": size, "files": files,
            "isDir": isDir, "mtime": mtime, "denied": denied,
            "pct": parentSize > 0 ? (Double(size) / Double(parentSize) * 1000).rounded() / 10 : 0,
            "rule": ruleJSON(info), "protected": matcher.isProtected(path),
        ]
    }

    private func node(_ rawPath: String?) throws -> [String: Any] {
        let s = try requireScan()
        let path = (rawPath?.isEmpty == false) ? (rawPath! as NSString).standardizingPath : s.rootPath
        guard let n = s.index[path] else { throw Failure(message: "Folder tidak ada di hasil pindai: \(path)") }

        var items: [[String: Any]] = []
        let shown = n.children.prefix(300)
        for c in shown {
            items.append(itemJSON(path: c.path, name: c.name, size: c.size, files: c.files, isDir: true,
                                  mtime: c.mtime, info: c.info, parentSize: n.size, denied: c.denied))
        }
        var listed: Int64 = 0
        for f in n.top {
            items.append(itemJSON(path: f.path, name: f.name, size: f.size, files: 1, isDir: false, mtime: f.mtime,
                                  info: s.fileRule(f.path, parent: n), parentSize: n.size))
            listed += f.size
        }
        let hidden = n.children.dropFirst(300)
        let other = n.own - listed + hidden.reduce(0) { $0 + $1.size }
        let otherCount = n.files - shown.reduce(0) { $0 + $1.files } - n.top.count
        if other > 0 && otherCount > 0 {
            var label = "\(Format.count(otherCount)) file kecil lainnya"
            if !hidden.isEmpty { label += " (termasuk \(hidden.count) folder kecil)" }
            items.append([
                "name": label, "path": NSNull(), "display": "", "size": other, "files": otherCount,
                "isDir": false, "mtime": 0, "other": true,
                "pct": n.size > 0 ? (Double(other) / Double(n.size) * 1000).rounded() / 10 : 0,
                "rule": ruleJSON(RuleInfo(rule: n.rule, inherited: true, depth: n.depth + 1)), "protected": true,
            ])
        }
        items.sort { (($0["size"] as? Int64) ?? 0) > (($1["size"] as? Int64) ?? 0) }

        var crumbs: [[String: String]] = []
        var p: Node? = n
        while let cur = p {
            crumbs.append(["name": cur.parent == nil ? matcher.display(cur.path) : cur.name, "path": cur.path])
            p = cur.parent
        }
        let me = itemJSON(path: n.path, name: n.name, size: n.size, files: n.files, isDir: true, mtime: n.mtime,
                          info: n.info, parentSize: n.parent?.size ?? n.size, denied: n.denied)
        return ["node": me, "items": items, "crumbs": Array(crumbs.reversed())]
    }

    private func summary() throws -> [String: Any] {
        let s = try requireScan()
        let disk = Disks.disk(for: s.rootPath, in: disks())
        let sum = s.summary(disk: disk)
        return [
            "root": s.rootPath, "display": sum.display, "scanned": sum.scanned, "files": sum.files,
            "dirs": s.progress.dirs, "elapsed": (sum.elapsed * 10).rounded() / 10,
            "categories": sum.categories.map { ["id": $0.id, "label": $0.label, "size": $0.size] as [String: Any] },
            "disk": disk.map(diskJSON) ?? NSNull(), "wholeDisk": sum.wholeDisk, "unscanned": sum.unscanned,
            "safeTotal": sum.safeTotal, "cautionTotal": sum.cautionTotal, "denied": sum.denied,
            "insights": sum.insights.map { ["level": $0.level.rawValue, "text": $0.text] },
        ]
    }

    private func recommendations() throws -> [String: Any] {
        let s = try requireScan()
        let groups: [[String: Any]] = s.recommendations().map { g in
            [
                "id": g.id, "rule": ruleJSON(RuleInfo(rule: g.rule)), "kind": g.kind.rawValue, "total": g.total,
                "items": g.items.map { i in
                    ["path": i.path, "display": i.display, "size": i.size, "files": i.files, "mtime": i.mtime,
                     "isDir": i.isDir] as [String: Any]
                },
            ]
        }
        return ["groups": groups, "trash": TrashService.size()]
    }

    private func largeFiles() throws -> [String: Any] {
        let s = try requireScan()
        let items = s.largestFiles(limit: 150).map { f in
            itemJSON(path: f.path, name: f.name, size: f.size, files: 1, isDir: false, mtime: f.mtime,
                     info: s.fileRule(f.path, parent: s.parentNode(of: f.path)), parentSize: 0)
        }
        return ["items": items]
    }

    private func trash(_ raw: [[String: Any]]) throws -> [String: Any] {
        let s = try requireScan()
        let reqs = raw.compactMap { d -> Cleaner.Request? in
            guard let p = d["path"] as? String else { return nil }
            return Cleaner.Request(path: p, contents: d["contents"] as? Bool ?? false)
        }
        let res = Cleaner(scan: s).trash(reqs)
        return [
            "done": res.done.map { ["path": $0, "display": matcher.display($0)] },
            "errors": res.errors.map { ["path": $0.path, "display": matcher.display($0.path), "error": $0.message] },
            "freed": res.freed,
            "note": "File ada di Sampah. Ruang disk baru benar-benar kosong setelah Sampah dikosongkan.",
        ]
    }
}
