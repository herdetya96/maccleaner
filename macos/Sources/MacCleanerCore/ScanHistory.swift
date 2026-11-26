import Foundation

/// Riwayat pemindaian (ukuran, jumlah file, durasi) per folder — untuk
/// memperkirakan progres & sisa waktu pemindaian berikutnya.
/// Formatnya sama dengan versi web (maccleaner/history.py).
public enum ScanHistory {
    public struct Entry: Codable, Sendable {
        public var bytes: Int64
        public var files: Int
        public var duration: Double
        public var when: Int
    }

    public static var fileURL: URL {
        let base: URL
        if let override = ProcessInfo.processInfo.environment["MACCLEANER_DATA_DIR"] {
            base = URL(fileURLWithPath: override)
        } else {
            #if os(macOS)
            base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support/MacCleaner")
            #else
            base = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".local/share/maccleaner")
            #endif
        }
        return base.appendingPathComponent("scan-history.json")
    }

    static func loadAll() -> [String: Entry] {
        guard let data = try? Data(contentsOf: fileURL),
              let all = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return all
    }

    public static func load(_ path: String) -> Entry? {
        guard let e = loadAll()[path], e.bytes > 0 else { return nil }
        return e
    }

    public static func save(_ path: String, bytes: Int64, files: Int, duration: TimeInterval) {
        var all = loadAll()
        all[path] = Entry(bytes: bytes, files: files, duration: (duration * 100).rounded() / 100,
                          when: Int(Date().timeIntervalSince1970))
        if all.count > 50 {
            for (k, _) in all.sorted(by: { $0.value.when < $1.value.when }).prefix(all.count - 50) {
                all.removeValue(forKey: k)
            }
        }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try JSONEncoder().encode(all).write(to: fileURL, options: .atomic)
        } catch {
            // Riwayat hanya bonus; abaikan kegagalan.
        }
    }

    /// Isi perkiraan total untuk `scan` berdasarkan riwayat atau pemakaian disk.
    public static func prepare(_ scan: Scan, disks: [DiskInfo]) {
        if let h = load(scan.rootPath) {
            scan.setEstimate(.history, bytes: h.bytes, files: h.files, duration: h.duration)
        } else if let d = disks.first(where: { $0.mount == scan.rootPath }) {
            scan.setEstimate(.disk, bytes: d.used)
        } else {
            scan.setEstimate(.tree)
        }
    }

    /// Simpan hasil pemindaian yang selesai penuh.
    public static func remember(_ scan: Scan) {
        guard scan.state == .done, let root = scan.root else { return }
        save(scan.rootPath, bytes: root.size, files: root.files, duration: scan.elapsed)
    }
}
