import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// File besar yang diingat pemindai.
public struct FileEntry: Identifiable, Hashable, Sendable {
    public let size: Int64
    public let path: String
    public let mtime: TimeInterval
    public var id: String { path }
    public var name: String { (path as NSString).lastPathComponent }
}

/// Satu folder di hasil pindai.
public final class Node: Identifiable {
    public let name: String
    public let path: String
    public weak var parent: Node?
    public internal(set) var size: Int64 = 0
    /// Total ukuran file yang langsung ada di folder ini.
    public internal(set) var own: Int64 = 0
    public internal(set) var files: Int = 0
    public internal(set) var children: [Node] = []
    /// File terbesar langsung di folder ini.
    public internal(set) var top: [FileEntry] = []
    public let rule: Rule?
    public let inherited: Bool
    public internal(set) var depth: Int = 0
    public internal(set) var denied = false
    public let mtime: TimeInterval

    public var id: String { path }
    public var info: RuleInfo { RuleInfo(rule: rule, inherited: inherited, depth: depth) }

    init(name: String, path: String, parent: Node?, rule: Rule?, inherited: Bool, mtime: TimeInterval) {
        self.name = name
        self.path = path
        self.parent = parent
        self.rule = rule
        self.inherited = inherited
        self.mtime = mtime
    }

    func walk(_ body: (Node) -> Void) {
        var stack: [Node] = [self]
        while let n = stack.popLast() {
            body(n)
            stack.append(contentsOf: n.children)
        }
    }
}

/// Progres pemindaian (dibaca UI secara berkala).
public struct ScanProgress: Sendable {
    public var files = 0
    public var dirs = 0
    public var bytes: Int64 = 0
    public var current = ""
}

/// Pemindai disk. Panggil `run()` di thread latar; hasilnya dibaca setelah selesai.
public final class Scan: @unchecked Sendable {
    public enum State: Equatable, Sendable { case idle, running, done, cancelled, failed(String) }

    public static let topPerDir = 12
    public static let topFileMin: Int64 = 256 * 1024
    public static let topGlobal = 300

    public let rootPath: String
    public let matcher: RuleMatcher
    public private(set) var state: State = .idle
    public private(set) var started = Date()
    public private(set) var finished: Date?
    public private(set) var root: Node?
    public private(set) var index: [String: Node] = [:]
    public private(set) var topFiles: [FileEntry] = []
    public private(set) var deniedCount = 0
    public private(set) var deniedSample: [String] = []

    private let lock = NSLock()
    private var _progress = ScanProgress()
    private var cancelled = false

    public init(path: String, matcher: RuleMatcher) {
        var p = (path as NSString).expandingTildeInPath
        p = (p as NSString).standardizingPath
        self.rootPath = p.isEmpty ? "/" : p
        self.matcher = matcher
    }

    public var progress: ScanProgress {
        lock.lock(); defer { lock.unlock() }
        return _progress
    }

    public func cancel() {
        lock.lock(); cancelled = true; lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    public var elapsed: TimeInterval { (finished ?? Date()).timeIntervalSince(started) }

    // MARK: - Pemindaian

    public func run() {
        state = .running
        started = Date()
        do {
            try scan()
            state = isCancelled ? .cancelled : .done
        } catch {
            state = .failed(error.localizedDescription)
        }
        finished = Date()
        lock.lock(); _progress.current = ""; lock.unlock()
    }

    struct Stat {
        var isDir = false
        var isFile = false
        var isLink = false
        var dev: UInt64 = 0
        var ino: UInt64 = 0
        var nlink = 0
        var size: Int64 = 0
        var mtime: TimeInterval = 0
    }

    static func lstatPath(_ path: String) -> Stat? {
        var st = stat()
        guard lstat(path, &st) == 0 else { return nil }
        var r = Stat()
        let fmt = st.st_mode & S_IFMT
        r.isDir = fmt == S_IFDIR
        r.isFile = fmt == S_IFREG
        r.isLink = fmt == S_IFLNK
        r.dev = UInt64(truncatingIfNeeded: st.st_dev)
        r.ino = UInt64(truncatingIfNeeded: st.st_ino)
        r.nlink = Int(truncatingIfNeeded: st.st_nlink)
        // Ukuran nyata di disk (blok terpakai), bukan ukuran logis.
        r.size = Int64(truncatingIfNeeded: st.st_blocks) * 512
        #if canImport(Darwin)
        r.mtime = TimeInterval(st.st_mtimespec.tv_sec)
        #else
        r.mtime = TimeInterval(st.st_mtim.tv_sec)
        #endif
        return r
    }

    private func skipPaths() -> Set<String> {
        #if os(macOS)
        // Volume lain di container APFS yang sama & disk eksternal.
        var s: Set<String> = ["/System/Volumes", "/Volumes", "/dev", "/net", "/home", "/private/var/vm"]
        #else
        var s: Set<String> = ["/proc", "/sys", "/dev", "/run"]
        #endif
        s.remove(rootPath)
        return s
    }

    private func scan() throws {
        guard let rootSt = Scan.lstatPath(rootPath), rootSt.isDir else {
            throw NSError(domain: "MacCleaner", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Bukan folder: \(rootPath)"])
        }
        var allowed: Set<UInt64> = [rootSt.dev]
        #if os(macOS)
        if rootPath == "/", let data = Scan.lstatPath("/System/Volumes/Data") {
            // Sejak Catalina, data pengguna ada di volume "Data" yang tersambung
            // ke / lewat firmlink (/Users, /Applications, ...).
            allowed.insert(data.dev)
        }
        #endif
        let skip = skipPaths()

        // Aturan untuk root: perhitungkan aturan milik leluhurnya.
        var ancestors: [String] = []
        var p = (rootPath as NSString).deletingLastPathComponent
        while rootPath != "/" {
            ancestors.append(p)
            if p == "/" || p.isEmpty { break }
            p = (p as NSString).deletingLastPathComponent
        }
        var prule: Rule?
        var pinh = false
        var depth = 0
        for a in ancestors.reversed() {
            (prule, pinh) = matcher.resolve(a, parent: prule, parentInherited: pinh)
            depth = pinh ? depth + 1 : 0
        }
        let (rrule, rinh) = matcher.resolve(rootPath, parent: prule, parentInherited: pinh)
        let name = rootPath == "/" ? "/" : (rootPath as NSString).lastPathComponent
        let root = Node(name: name, path: rootPath, parent: nil, rule: rrule, inherited: rinh,
                        mtime: rootSt.mtime)
        root.depth = rinh ? depth + 1 : 0
        self.root = root
        var index: [String: Node] = [rootPath: root]
        var nodes: [Node] = [root]
        var stack: [Node] = [root]
        var seenInodes = Set<[UInt64]>()
        var top: [FileEntry] = []
        var topMin: Int64 = 0
        var files = 0
        var total: Int64 = 0
        var lastTick = Date()

        while let node = stack.popLast() {
            if isCancelled { break }
            guard let dir = opendir(node.path) else {
                if errno == EACCES || errno == EPERM {
                    node.denied = true
                    deniedCount += 1
                    if deniedSample.count < 200 { deniedSample.append(node.path) }
                }
                continue
            }
            let base = node.path == "/" ? "" : node.path
            while let ent = readdir(dir) {
                let entName: String = withUnsafePointer(to: ent.pointee.d_name) { ptr in
                    String(cString: UnsafeRawPointer(ptr).assumingMemoryBound(to: CChar.self))
                }
                if entName == "." || entName == ".." { continue }
                let path = base + "/" + entName
                guard let st = Scan.lstatPath(path) else { continue }
                if st.isDir {
                    if !allowed.contains(st.dev) || skip.contains(path) { continue }
                    let (crule, cinh) = matcher.resolve(path, parent: node.rule, parentInherited: node.inherited)
                    let child = Node(name: entName, path: path, parent: node, rule: crule,
                                     inherited: cinh, mtime: st.mtime)
                    if cinh { child.depth = node.depth + 1 }
                    node.children.append(child)
                    nodes.append(child)
                    stack.append(child)
                    index[path] = child
                } else if st.isFile || st.isLink {
                    if st.isFile && st.nlink > 1 {
                        // Hardlink: hitung sekali saja.
                        let key = [st.dev, st.ino]
                        if seenInodes.contains(key) { continue }
                        seenInodes.insert(key)
                    }
                    node.own += st.size
                    node.files += 1
                    files += 1
                    total += st.size
                    if st.size >= Scan.topFileMin {
                        let entry = FileEntry(size: st.size, path: path, mtime: st.mtime)
                        if node.top.count < Scan.topPerDir {
                            node.top.append(entry)
                        } else if let mi = node.top.indices.min(by: { node.top[$0].size < node.top[$1].size }),
                                  st.size > node.top[mi].size {
                            node.top[mi] = entry
                        }
                        if top.count < Scan.topGlobal {
                            top.append(entry)
                            if top.count == Scan.topGlobal { topMin = top.map(\.size).min() ?? 0 }
                        } else if st.size > topMin,
                                  let mi = top.indices.min(by: { top[$0].size < top[$1].size }) {
                            top[mi] = entry
                            topMin = top.map(\.size).min() ?? 0
                        }
                    }
                }
            }
            closedir(dir)

            let now = Date()
            if now.timeIntervalSince(lastTick) > 0.1 {
                lastTick = now
                lock.lock()
                _progress = ScanProgress(files: files, dirs: nodes.count, bytes: total, current: node.path)
                lock.unlock()
            }
        }

        lock.lock()
        _progress = ScanProgress(files: files, dirs: nodes.count, bytes: total, current: "")
        lock.unlock()

        // Agregasi ukuran dari bawah ke atas (anak selalu dibuat setelah induknya).
        for n in nodes { n.size = n.own }
        for n in nodes.reversed() {
            if let parent = n.parent {
                parent.size += n.size
                parent.files += n.files
            }
        }
        for n in nodes {
            n.children.sort { $0.size > $1.size }
            n.top.sort { $0.size > $1.size }
        }
        self.index = index
        self.topFiles = top.sorted { $0.size > $1.size }
    }

    // MARK: - Kueri hasil

    /// Aturan untuk sebuah file: (rule, inherited, depth).
    public func fileRule(_ path: String, parent: Node?) -> RuleInfo {
        let (rule, inh) = matcher.resolve(path, parent: parent?.rule, parentInherited: parent?.inherited ?? false)
        let depth = (inh && parent != nil) ? parent!.depth + 1 : 0
        return RuleInfo(rule: rule, inherited: inh, depth: depth)
    }

    public func parentNode(of path: String) -> Node? {
        index[(path as NSString).deletingLastPathComponent]
    }

    public func largestFiles(limit: Int = 150) -> [FileEntry] {
        Array(topFiles.prefix(limit))
    }

    /// Total ukuran per kategori: [kategori: byte].
    public func categoryTotals() -> [String: Int64] {
        var totals: [String: Int64] = [:]
        root?.walk { n in
            totals[n.rule?.category ?? "other", default: 0] += n.own
        }
        return totals
    }

    /// Catat bahwa `path` sudah dibuang. Mengembalikan jumlah byte yang dikurangi.
    @discardableResult
    public func remove(_ path: String) -> Int64 {
        var size: Int64 = 0
        var files = 0
        var parent: Node?
        if let node = index[path] {
            size = node.size
            files = node.files
            parent = node.parent
            parent?.children.removeAll { $0 === node }
            node.walk { n in _ = self.index.removeValue(forKey: n.path) }
            topFiles.removeAll { $0.path == path || $0.path.hasPrefix(path + "/") }
        } else {
            parent = parentNode(of: path)
            files = 1
            if let e = topFiles.first(where: { $0.path == path }) { size = e.size }
            if let p = parent {
                if size == 0, let e = p.top.first(where: { $0.path == path }) { size = e.size }
                p.top.removeAll { $0.path == path }
                p.own = max(0, p.own - size)
            }
            topFiles.removeAll { $0.path == path }
        }
        var p = parent
        while let cur = p {
            cur.size = max(0, cur.size - size)
            cur.files = max(0, cur.files - files)
            p = cur.parent
        }
        parent?.children.sort { $0.size > $1.size }
        return size
    }

    /// Setelah isi sebuah folder dibuang: hitung ulang file yang tersisa di folder itu.
    @discardableResult
    public func refreshOwnFiles(_ path: String) -> Int64 {
        guard let node = index[path] else { return 0 }
        var remaining: Int64 = 0
        if let names = try? FileManager.default.contentsOfDirectory(atPath: path) {
            for name in names {
                if let st = Scan.lstatPath(path + "/" + name), !st.isDir { remaining += st.size }
            }
        }
        let diff = max(0, node.own - remaining)
        node.own = remaining
        node.top.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        var p: Node? = node
        while let cur = p {
            cur.size = max(0, cur.size - diff)
            p = cur.parent
        }
        return diff
    }

    /// Apakah `path` file yang tercatat di hasil pindai?
    public func knownFile(_ path: String) -> FileEntry? {
        if let e = topFiles.first(where: { $0.path == path }) { return e }
        return parentNode(of: path)?.top.first(where: { $0.path == path })
    }
}
