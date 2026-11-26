import Foundation
import XCTest
@testable import MacCleanerCore

final class RuleTests: XCTestCase {
    let m = RuleMatcher(home: "/Users/budi")

    func testGlob() {
        XCTAssertEqual(globToRegex("**/node_modules"), "(?:.*/)?node_modules")
    }

    func testKnownPaths() {
        let cases: [(String, String, Safety)] = [
            ("/Users/budi/Library/Caches", "user-caches", .aman),
            ("/Users/budi/Library/Caches/com.spotify.client", "user-caches-item", .aman),
            ("/Users/budi/Library/Caches/Homebrew", "brew-cache", .aman),
            ("/Users/budi/Library/Developer/Xcode/DerivedData", "xcode-deriveddata", .aman),
            ("/Users/budi/Library/Developer/Xcode/iOS DeviceSupport", "xcode-devicesupport", .aman),
            ("/Users/budi/Library/Mobile Documents", "icloud", .jangan),
            ("/Users/budi/Library/Application Support/MobileSync/Backup", "ios-backup", .hati),
            ("/Users/budi/code/app/node_modules", "node-modules", .aman),
            ("/Users/budi/Downloads/Zoom.dmg", "installer", .aman),
            ("/Users/budi/Downloads", "downloads", .periksa),
            ("/Users/budi/Pictures/Photos Library.photoslibrary", "photos", .jangan),
            ("/System", "system", .jangan),
            ("/Applications/Slack.app", "app-bundle", .hati),
            ("/Users/budi/Library/Application Support/Slack/Cache", "app-caches", .aman),
            ("/Users/budi/.cache/huggingface", "huggingface", .hati),
        ]
        for (path, id, safety) in cases {
            let r = m.match(path)
            XCTAssertEqual(r?.id, id, path)
            XCTAssertEqual(r?.safety, safety, path)
        }
        XCTAssertEqual(m.match("/users/budi/library/caches")?.id, "user-caches")
        XCTAssertNil(m.match("/Users/budi/proyek/web/src"))
    }

    func testLockAndInheritance() {
        let photos = m.resolve("/Users/budi/Pictures/P.photoslibrary", parent: nil)
        let mov = m.resolve("/Users/budi/Pictures/P.photoslibrary/originals/a.mov",
                            parent: photos.rule, parentInherited: photos.inherited)
        XCTAssertEqual(mov.rule?.id, "photos")
        XCTAssertTrue(mov.inherited)

        let lib = m.resolve("/Users/budi/Library", parent: nil)
        XCTAssertNil(m.resolve("/Users/budi/Library/Foo", parent: lib.rule).rule)
    }

    func testProtected() {
        for p in ["/", "/System", "/Users/budi", "/Users/budi/Library", "/Users/budi/Documents", "/Users/lain"] {
            XCTAssertTrue(m.isProtected(p), p)
        }
        XCTAssertFalse(m.isProtected("/Users/budi/Library/Caches"))
    }

    func testFormat() {
        XCTAssertEqual(Format.bytes(512), "512 B")
        XCTAssertEqual(Format.bytes(1_500_000), "1,5 MB")
        XCTAssertEqual(Format.bytes(250_000_000_000), "250 GB")
    }
}

final class ScanTests: XCTestCase {
    var tmp = ""
    var home = ""

    func write(_ rel: String, _ size: Int) throws {
        let path = home + "/" + rel
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        try Data(repeating: 1, count: size).write(to: URL(fileURLWithPath: path))
    }

    override func setUpWithError() throws {
        tmp = NSTemporaryDirectory() + "mc-test-" + UUID().uuidString
        // Pakai path tanpa symlink (/var → /private/var di macOS).
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        tmp = URL(fileURLWithPath: tmp).resolvingSymlinksInPath().path
        home = tmp + "/Users/budi"
        try write("Library/Caches/com.spotify.client/data.bin", 300_000)
        try write("Library/Caches/com.apple.Safari/cache.db", 200_000)
        try write("Library/Developer/Xcode/DerivedData/MyApp-abc/Build/x.o", 400_000)
        try write("Library/Mobile Documents/com~apple~CloudDocs/thesis.pages", 150_000)
        try write("Library/Application Support/MobileSync/Backup/123/Manifest.db", 400_000)
        try write("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", 500_000)
        try write("proyek/web/node_modules/react/index.js", 350_000)
        try write("proyek/web/src/app.js", 1_000)
        try write("Downloads/Zoom.dmg", 600_000)
        try write("Pictures/Photos Library.photoslibrary/originals/IMG_1.mov", 700_000)
        try write("Documents/skripsi.docx", 50_000)
        try write(".Trash/lama.zip", 300_000)
        try FileManager.default.linkItem(atPath: home + "/Documents/skripsi.docx",
                                         toPath: home + "/Documents/skripsi-link.docx")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: tmp)
    }

    func makeScan() -> Scan {
        let s = Scan(path: home, matcher: RuleMatcher(home: home))
        s.run()
        return s
    }

    func testSizesAndHardlinks() {
        let s = makeScan()
        XCTAssertEqual(s.state, .done)
        let root = s.root!
        XCTAssertEqual(root.size, root.children.reduce(0) { $0 + $1.size } + root.own)
        XCTAssertEqual(root.files, 12) // 13 entri, 1 hardlink ganda
        XCTAssertGreaterThanOrEqual(s.index[home + "/Library/Caches"]!.size, 500_000)
    }

    func testRecommendations() {
        let s = makeScan()
        var byRule: [String: [String]] = [:]
        for g in s.recommendations(minSize: 1) { byRule[g.rule.id, default: []] += g.items.map(\.path) }
        XCTAssertTrue(byRule["user-caches-item"]?.contains(home + "/Library/Caches/com.spotify.client") ?? false)
        XCTAssertTrue(byRule["xcode-deriveddata"]?.contains(home + "/Library/Developer/Xcode/DerivedData/MyApp-abc") ?? false)
        XCTAssertTrue(byRule["node-modules"]?.contains(home + "/proyek/web/node_modules") ?? false)
        XCTAssertTrue(byRule["installer"]?.contains(home + "/Downloads/Zoom.dmg") ?? false)
        XCTAssertTrue(byRule["ios-backup"]?.contains(home + "/Library/Application Support/MobileSync/Backup") ?? false)
        let all = byRule.values.flatMap { $0 }
        XCTAssertFalse(all.contains { $0.contains("Mobile Documents") })
        XCTAssertFalse(all.contains { $0.contains("photoslibrary") })
    }

    func testCategories() {
        let t = makeScan().categoryTotals()
        XCTAssertGreaterThan(t["cache"] ?? 0, 0)
        XCTAssertGreaterThan(t["media"] ?? 0, 0)
        XCTAssertGreaterThan(t["cloud"] ?? 0, 0)
    }

    func testCleanerRefusesDangerous() {
        let s = makeScan()
        let c = Cleaner(scan: s)
        let bad = [
            home + "/Library/Mobile Documents",
            home + "/Pictures/Photos Library.photoslibrary/originals",
            home + "/Library",
            home + "/Documents",
            home + "/Library/Containers/com.docker.docker",
            home + "/Library/Application Support/MobileSync/Backup/123/Manifest.db",
            home + "/.Trash/lama.zip",
            "/etc",
            home + "/../budi/Library",
        ]
        for p in bad {
            XCTAssertThrowsError(try c.check(p), p)
        }
        XCTAssertNoThrow(try c.check(home + "/proyek/web/node_modules"))
        XCTAssertNoThrow(try c.check(home + "/Library/Application Support/MobileSync/Backup/123"))
        XCTAssertNoThrow(try c.check(home + "/Downloads/Zoom.dmg"))
    }

    func testPartOf() {
        let s = makeScan()
        let path = home + "/Library/Application Support/MobileSync/Backup/123/Manifest.db"
        let info = s.fileRule(path, parent: s.parentNode(of: path))
        XCTAssertTrue(info.partOf)
        XCTAssertFalse(info.deletable)
    }

    func testRemoveUpdatesSizes() {
        let s = makeScan()
        let before = s.root!.size
        let freed = s.remove(home + "/proyek/web/node_modules")
        XCTAssertGreaterThan(freed, 0)
        XCTAssertEqual(s.root!.size, before - freed)
        XCTAssertNil(s.index[home + "/proyek/web/node_modules"])
    }
}
