import Foundation

/// Memindahkan ke Sampah (bukan hapus permanen) dan mengosongkan Sampah.
public enum TrashService {
    public struct Outcome: Sendable {
        public let path: String
        public let ok: Bool
        public let message: String
    }

    public static func moveToTrash(_ paths: [String]) -> [Outcome] {
        paths.map { path in
            do {
                try trashOne(path)
                return Outcome(path: path, ok: true, message: "Dipindahkan ke Sampah")
            } catch {
                return Outcome(path: path, ok: false, message: friendly(error))
            }
        }
    }

    static func trashOne(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        #if os(macOS)
        // Sama seperti Finder: mendukung "Kembalikan" dan disk eksternal.
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        #else
        // Sampah freedesktop (dipakai untuk tes di Linux).
        let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
            ?? (NSHomeDirectory() + "/.local/share")
        let files = base + "/Trash/files"
        let info = base + "/Trash/info"
        try FileManager.default.createDirectory(atPath: files, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(atPath: info, withIntermediateDirectories: true)
        var name = url.lastPathComponent
        var i = 1
        while FileManager.default.fileExists(atPath: files + "/" + name) {
            name = url.lastPathComponent + " \(i)"
            i += 1
        }
        let escaped = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        try "[Trash Info]\nPath=\(escaped)\nDeletionDate=\(ISO8601DateFormatter().string(from: Date()))\n"
            .write(toFile: info + "/" + name + ".trashinfo", atomically: true, encoding: .utf8)
        try FileManager.default.moveItem(atPath: path, toPath: files + "/" + name)
        #endif
    }

    public static func friendly(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain {
            switch ns.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return "Izin ditolak (file milik sistem/admin atau sedang dipakai)."
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
                return "File sudah tidak ada."
            default: break
            }
        }
        return ns.localizedDescription
    }

    public static var trashFolder: String {
        #if os(macOS)
        return NSHomeDirectory() + "/.Trash"
        #else
        let base = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
            ?? (NSHomeDirectory() + "/.local/share")
        return base + "/Trash/files"
        #endif
    }

    /// Ukuran isi Sampah (0 bila tidak bisa dibaca).
    public static func size() -> Int64 {
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(atPath: trashFolder) else { return 0 }
        while let rel = e.nextObject() as? String {
            if let st = Scan.lstatPath(trashFolder + "/" + rel), !st.isDir { total += st.size }
        }
        return total
    }

    /// Kosongkan Sampah — PERMANEN.
    public static func empty() -> (ok: Bool, message: String) {
        #if os(macOS)
        var err: NSDictionary?
        let script = NSAppleScript(source: "tell application \"Finder\" to empty trash")
        script?.executeAndReturnError(&err)
        if let err = err {
            return (false, "Gagal mengosongkan Sampah lewat Finder: \(err[NSAppleScript.errorMessage] ?? err)")
        }
        return (true, "Sampah dikosongkan.")
        #else
        let fm = FileManager.default
        var errors = 0
        for dir in [trashFolder, (trashFolder as NSString).deletingLastPathComponent + "/info"] {
            for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] {
                do { try fm.removeItem(atPath: dir + "/" + name) } catch { errors += 1 }
            }
        }
        return errors == 0 ? (true, "Sampah dikosongkan.") : (false, "\(errors) item tidak bisa dihapus.")
        #endif
    }
}

/// Menerapkan semua pemeriksaan keamanan sebelum membuang ke Sampah.
public final class Cleaner {
    public struct Request: Hashable, Sendable {
        public let path: String
        /// Buang isinya saja (foldernya tetap).
        public let contents: Bool
        public init(path: String, contents: Bool = false) {
            self.path = path
            self.contents = contents
        }
    }

    public struct Result: Sendable {
        public var done: [String] = []
        public var errors: [(path: String, message: String)] = []
        public var freed: Int64 = 0
    }

    public let scan: Scan
    var matcher: RuleMatcher { scan.matcher }

    public init(scan: Scan) {
        self.scan = scan
    }

    /// Lempar error berisi alasan bila `path` tidak boleh dibuang.
    public func check(_ rawPath: String) throws -> RuleInfo {
        func fail(_ msg: String) -> NSError {
            NSError(domain: "MacCleaner", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
        }
        guard rawPath.hasPrefix("/") else { throw fail("Path tidak valid.") }
        let path = (rawPath as NSString).standardizingPath
        let root = scan.rootPath == "/" ? "" : scan.rootPath
        guard path.hasPrefix(root + "/") && path != scan.rootPath else {
            throw fail("Di luar folder yang dipindai.")
        }
        if matcher.isProtected(path) { throw fail("Folder penting sistem/pengguna — dilindungi.") }
        guard Scan.lstatPath(path) != nil else { throw fail("Sudah tidak ada.") }
        let info: RuleInfo
        if let node = scan.index[path] {
            info = node.info
        } else if scan.knownFile(path) != nil || scan.parentNode(of: path) != nil {
            info = scan.fileRule(path, parent: scan.parentNode(of: path))
        } else {
            throw fail("Tidak ada di hasil pindai.")
        }
        if let r = info.rule {
            if r.safety == .jangan { throw fail("\(r.title) — jangan dihapus. \(r.how)") }
            if !r.deletable {
                throw fail("\(r.title) harus dibersihkan lewat caranya sendiri: \(r.how) \(r.command)"
                    .trimmingCharacters(in: .whitespaces))
            }
            if !canDelete(r, depth: info.depth) {
                throw fail("Bagian dalam dari \"\(r.title)\" — buang seluruh foldernya, bukan file di dalamnya.")
            }
        }
        return info
    }

    public func trash(_ requests: [Request]) -> Result {
        var result = Result()
        var targets: [String] = []
        var clearedDirs: [String] = []
        for req in requests {
            let path = (req.path as NSString).standardizingPath
            do {
                _ = try check(path)
            } catch {
                result.errors.append((path, error.localizedDescription))
                continue
            }
            if req.contents, let st = Scan.lstatPath(path), st.isDir {
                let node = scan.index[path]
                let names = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
                for name in names {
                    let child = path + "/" + name
                    let (crule, cinh) = matcher.resolve(child, parent: node?.rule,
                                                        parentInherited: node?.inherited ?? false)
                    let cdepth = (cinh && node != nil) ? node!.depth + 1 : 0
                    if let r = crule, r.safety == .jangan || !canDelete(r, depth: cdepth) { continue }
                    targets.append(child)
                }
                clearedDirs.append(path)
            } else {
                targets.append(path)
            }
        }
        for o in TrashService.moveToTrash(targets) {
            if o.ok {
                result.freed += scan.remove(o.path)
                result.done.append(o.path)
            } else {
                result.errors.append((o.path, o.message))
            }
        }
        for d in clearedDirs { result.freed += scan.refreshOwnFiles(d) }
        return result
    }
}
