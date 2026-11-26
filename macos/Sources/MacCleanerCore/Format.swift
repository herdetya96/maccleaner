import Foundation

public enum Format {
    /// Ukuran dalam satuan desimal (1 GB = 1000³ byte), sama seperti Finder.
    public static func bytes(_ value: Int64) -> String {
        var n = Double(value)
        let units = ["B", "KB", "MB", "GB", "TB"]
        var i = 0
        while abs(n) >= 999.95 && i < units.count - 1 {
            n /= 1000
            i += 1
        }
        if i == 0 { return "\(value) B" }
        let digits = n >= 100 ? 0 : 1
        let text = String(format: "%.\(digits)f", n).replacingOccurrences(of: ".", with: ",")
        return "\(text) \(units[i])"
    }

    public static func count(_ value: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "id_ID")
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Lama waktu: "45 dtk", "3 mnt 12 dtk", "1 jam 5 mnt".
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds).rounded())
        if s < 60 { return "\(s) dtk" }
        if s < 3600 {
            let m = s / 60, r = s % 60
            return r > 0 ? "\(m) mnt \(r) dtk" : "\(m) mnt"
        }
        let h = s / 3600, m = (s % 3600) / 60
        return m > 0 ? "\(h) jam \(m) mnt" : "\(h) jam"
    }

    /// Sisa waktu dalam bahasa sehari-hari.
    public static func eta(_ seconds: TimeInterval?) -> String {
        guard let s = seconds else { return "Memperkirakan sisa waktu…" }
        if s < 10 { return "Hampir selesai…" }
        if s < 60 { return "Kurang dari 1 menit lagi" }
        if s < 3600 { return "Sekitar \(max(1, Int((s / 60).rounded()))) menit lagi" }
        let total = Int((s / 60).rounded())
        let h = total / 60, m = total % 60
        return m > 0 ? "Sekitar \(h) jam \(m) menit lagi" : "Sekitar \(h) jam lagi"
    }

    /// "3 bulan yang lalu"
    public static func ago(_ time: TimeInterval) -> String {
        guard time > 0 else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.unitsStyle = .full
        return f.localizedString(for: Date(timeIntervalSince1970: time), relativeTo: Date())
    }
}
