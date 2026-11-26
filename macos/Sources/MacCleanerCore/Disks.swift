import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public struct DiskInfo: Identifiable, Sendable {
    public enum Level: String, Sendable {
        case aman, sedang, tinggi, kritis

        public var message: String {
            switch self {
            case .kritis: return "Disk hampir penuh! macOS bisa melambat, gagal update, atau aplikasi crash."
            case .tinggi: return "Disk mulai penuh. Sisakan minimal 10–15% agar macOS lancar (swap, update, cache)."
            case .sedang: return "Masih aman, tapi ada baiknya mulai bersih-bersih."
            case .aman: return "Ruang disk masih lega."
            }
        }
    }

    public let name: String
    public let mount: String
    public let total: Int64
    /// Terpakai, dihitung seperti Finder (ruang "purgeable" dianggap tersedia).
    public let used: Int64
    /// Tersedia menurut Finder (termasuk ruang purgeable).
    public let available: Int64
    /// Ruang yang benar-benar kosong saat ini.
    public let free: Int64
    public let isInternal: Bool
    public let format: String
    public let isRoot: Bool

    public var id: String { mount }
    /// Ruang yang bisa dibebaskan macOS sendiri (cache sistem, snapshot lokal, iCloud).
    public var purgeable: Int64 { max(0, available - free) }
    public var percent: Double { total > 0 ? Double(used) / Double(total) * 100 : 0 }
    public var level: Level {
        let p = percent
        if p >= 95 { return .kritis }
        if p >= 85 { return .tinggi }
        if p >= 70 { return .sedang }
        return .aman
    }

    public init(name: String, mount: String, total: Int64, used: Int64, available: Int64, free: Int64,
                isInternal: Bool, format: String, isRoot: Bool) {
        self.name = name
        self.mount = mount
        self.total = total
        self.used = used
        self.available = available
        self.free = free
        self.isInternal = isInternal
        self.format = format
        self.isRoot = isRoot
    }
}

public enum Disks {
    public static func list() -> [DiskInfo] {
        #if os(macOS)
        let keys: [URLResourceKey] = [
            .volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
            .volumeLocalizedFormatDescriptionKey, .volumeIsBrowsableKey,
        ]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        var disks: [DiskInfo] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  let total = v.volumeTotalCapacity, total > 0 else { continue }
            let path = url.path
            if path.hasPrefix("/System/Volumes") { continue }
            let free = Int64(v.volumeAvailableCapacity ?? 0)
            let available = max(free, v.volumeAvailableCapacityForImportantUsage ?? free)
            disks.append(DiskInfo(
                name: v.volumeName ?? (path == "/" ? "Macintosh HD" : url.lastPathComponent),
                mount: path, total: Int64(total), used: max(0, Int64(total) - available),
                available: available, free: free, isInternal: v.volumeIsInternal ?? false,
                format: v.volumeLocalizedFormatDescription ?? "", isRoot: path == "/"))
        }
        return disks.sorted { ($0.isRoot ? 0 : 1, $0.name) < ($1.isRoot ? 0 : 1, $1.name) }
        #else
        var s = statvfs()
        guard statvfs("/", &s) == 0 else { return [] }
        let total = Int64(s.f_blocks) * Int64(s.f_frsize)
        let free = Int64(s.f_bavail) * Int64(s.f_frsize)
        return [DiskInfo(name: "Disk sistem", mount: "/", total: total, used: total - free,
                         available: free, free: free, isInternal: true, format: "", isRoot: true)]
        #endif
    }

    /// Disk tempat `path` berada.
    public static func disk(for path: String, in disks: [DiskInfo]) -> DiskInfo? {
        disks.filter { $0.mount == "/" || path == $0.mount || path.hasPrefix($0.mount + "/") }
            .max { $0.mount.count < $1.mount.count }
    }
}
