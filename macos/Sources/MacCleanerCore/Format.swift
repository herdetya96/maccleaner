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

    /// "3 bulan yang lalu"
    public static func ago(_ time: TimeInterval) -> String {
        guard time > 0 else { return "" }
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.unitsStyle = .full
        return f.localizedString(for: Date(timeIntervalSince1970: time), relativeTo: Date())
    }
}
