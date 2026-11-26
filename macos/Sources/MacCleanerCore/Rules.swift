import Foundation

/// Tingkat keamanan menghapus sebuah folder/file.
public enum Safety: String, CaseIterable, Sendable {
    case aman, hati, periksa, jangan, unknown

    public var label: String {
        switch self {
        case .aman: return "Aman dihapus"
        case .hati: return "Hati-hati"
        case .periksa: return "Periksa dulu"
        case .jangan: return "Jangan dihapus"
        case .unknown: return "Tidak dikenali"
        }
    }

    public var hint: String {
        switch self {
        case .aman: return "Dibuat ulang otomatis / tidak dibutuhkan"
        case .hati: return "Bisa dihapus, tapi ada akibatnya"
        case .periksa: return "File pribadi — Anda yang putuskan"
        case .jangan: return "Sistem / bisa merusak data"
        case .unknown: return "Belum dikenali — periksa sendiri"
        }
    }

    /// Urutan untuk menyortir (aman dulu).
    public var order: Int {
        switch self {
        case .aman: return 0
        case .hati: return 1
        case .periksa: return 2
        case .jangan: return 3
        case .unknown: return 4
        }
    }
}

public enum CleanMode: String, Sendable {
    /// Buang folder itu sendiri.
    case folder
    /// Buang isinya saja (foldernya tetap ada).
    case contents
}

/// Satu aturan basis pengetahuan. Data aturan ada di RuleData.swift
/// (dibuat otomatis dari maccleaner/rules.py).
public final class Rule: Identifiable, @unchecked Sendable {
    public let id: String
    public let patterns: [String]
    public let title: String
    public let category: String
    public let safety: Safety
    /// Isinya apa & kenapa bisa besar.
    public let why: String
    /// Apa yang terjadi kalau dihapus.
    public let effect: String
    /// Cara membersihkan yang benar.
    public let how: String
    /// Perintah Terminal (opsional).
    public let command: String
    /// Isi di bawahnya ikut aturan ini.
    public let inherit: Bool
    /// Isi di bawahnya tidak boleh menimpa aturan ini.
    public let lock: Bool
    public let mode: CleanMode
    public let deletable: Bool
    /// Boleh membuang item satu per satu di bagian dalam (cache, log, file pribadi).
    /// Kalau `false`, yang boleh dibuang hanya foldernya atau anak langsungnya.
    public let granular: Bool

    public init(id: String, patterns: [String], title: String, category: String, safety: Safety,
                why: String, effect: String, how: String, command: String,
                inherit: Bool, lock: Bool, mode: CleanMode, deletable: Bool, granular: Bool) {
        self.id = id
        self.patterns = patterns
        self.title = title
        self.category = category
        self.safety = safety
        self.why = why
        self.effect = effect
        self.how = how
        self.command = command
        self.inherit = inherit
        self.lock = lock
        self.mode = mode
        self.deletable = deletable && safety != .jangan
        self.granular = granular
    }

    public var categoryLabel: String { Categories.label(category) }
}

public enum Categories {
    public static func label(_ id: String) -> String {
        RuleTables.categories.first(where: { $0.id == id })?.label ?? id
    }
}

/// Bisakah item dengan aturan ini, di kedalaman `depth` di bawah folder pemilik
/// aturan, dibuang? (0 = folder itu sendiri, 1 = anak langsung, dst.)
public func canDelete(_ rule: Rule?, depth: Int) -> Bool {
    guard let rule = rule else { return true }
    if !rule.deletable { return false }
    return rule.granular || depth <= 1
}

/// Informasi aturan yang sudah "diterapkan" pada satu item, siap ditampilkan.
public struct RuleInfo: Sendable {
    public let rule: Rule?
    public let inherited: Bool
    public let depth: Int

    public init(rule: Rule?, inherited: Bool = false, depth: Int = 0) {
        self.rule = rule
        self.inherited = inherited
        self.depth = depth
    }

    public var safety: Safety { rule?.safety ?? .unknown }
    public var title: String { rule?.title ?? "Tidak dikenali" }
    public var category: String { rule?.category ?? "other" }
    public var why: String { rule?.why ?? "Aplikasi ini belum mengenali folder/file ini." }
    public var effect: String {
        rule?.effect ?? "Tidak diketahui — periksa isinya sendiri sebelum menghapus."
    }
    public var how: String { rule?.how ?? "Buka di Finder dan lihat isinya. Bila ragu, jangan dihapus." }
    public var command: String { rule?.command ?? "" }
    /// Mode efektif: isi di dalam folder yang dikenali selalu dibuang utuh.
    public var mode: CleanMode { (rule == nil || inherited) ? .folder : rule!.mode }
    public var deletable: Bool { canDelete(rule, depth: depth) }
    /// Bagian dalam dari sebuah paket (mis. file di dalam backup iPhone).
    public var partOf: Bool { (rule?.deletable ?? false) && !canDelete(rule, depth: depth) }
}

/// Ubah pola glob menjadi regex (tanpa anchor).
/// `*` = satu bagian path, `**/` = nol atau lebih folder, `/**` di akhir = semua isi.
public func globToRegex(_ pattern: String) -> String {
    var out = ""
    let chars = Array(pattern)
    var i = 0
    let n = chars.count
    func starts(_ s: String, at idx: Int) -> Bool {
        let sc = Array(s)
        guard idx + sc.count <= n else { return false }
        return Array(chars[idx..<(idx + sc.count)]) == sc
    }
    while i < n {
        if starts("**/", at: i) {
            out += "(?:.*/)?"
            i += 3
        } else if starts("/**", at: i) && i + 3 == n {
            out += "(?:/.*)?"
            i += 3
        } else if chars[i] == "*" {
            out += "[^/]*"
            i += 1
        } else if chars[i] == "?" {
            out += "[^/]"
            i += 1
        } else {
            out += NSRegularExpression.escapedPattern(for: String(chars[i]))
            i += 1
        }
    }
    return out
}

/// Mencocokkan path dengan semua aturan memakai satu regex gabungan.
public final class RuleMatcher: @unchecked Sendable {
    public let home: String
    public let rules: [Rule]
    private let regex: NSRegularExpression
    private let groupRules: [Rule]

    public init(home: String = NSHomeDirectory(), rules: [Rule] = Rule.all) {
        var h = home
        while h.count > 1 && h.hasSuffix("/") { h.removeLast() }
        self.home = h
        self.rules = rules
        var parts: [String] = []
        var groups: [Rule] = []
        for rule in rules {
            for var pat in rule.patterns {
                if pat == "~" || pat.hasPrefix("~/") {
                    pat = h + pat.dropFirst()
                }
                parts.append("(" + globToRegex(pat) + ")")
                groups.append(rule)
            }
        }
        self.groupRules = groups
        // Pola dibuat dari data yang sudah dikenal → tidak mungkin gagal.
        self.regex = try! NSRegularExpression(pattern: "^(?:" + parts.joined(separator: "|") + ")$",
                                              options: [.caseInsensitive])
    }

    public func match(_ path: String) -> Rule? {
        let ns = path as NSString
        guard let m = regex.firstMatch(in: path, options: [.anchored],
                                       range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }
        for i in 1..<m.numberOfRanges where m.range(at: i).location != NSNotFound {
            return groupRules[i - 1]
        }
        return nil
    }

    /// Aturan efektif untuk `path`, memperhitungkan aturan induknya.
    public func resolve(_ path: String, parent: Rule?, parentInherited: Bool = false) -> (rule: Rule?, inherited: Bool) {
        if let p = parent, p.lock { return (p, true) }
        if let own = match(path) { return (own, false) }
        if let p = parent, p.inherit { return (p, true) }
        return (nil, false)
    }

    /// Tampilkan path dengan `~` untuk folder rumah.
    public func display(_ path: String) -> String {
        if path == home { return "~" }
        if home != "/" && path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }

    /// Folder penting yang tidak boleh dibuang apa pun aturannya.
    public func isProtected(_ path: String) -> Bool {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        if RuleTables.protectedPaths.contains(p) || p == home { return true }
        let parent = (p as NSString).deletingLastPathComponent
        let name = (p as NSString).lastPathComponent
        if parent == home && RuleTables.protectedHomeChildren.contains(name) { return true }
        if parent == "/Users" || parent == "/home" { return true }
        return false
    }
}
