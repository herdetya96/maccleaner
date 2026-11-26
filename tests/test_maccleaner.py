import json
import os
import shutil
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

from maccleaner.rules import AMAN, HATI, JANGAN, PERIKSA, RuleMatcher, glob_to_regex
from maccleaner.scanner import Scan
from maccleaner.server import make_server


def write(path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(os.urandom(size))


class FakeHome:
    """Folder rumah tiruan yang mirip Mac."""

    def __init__(self):
        self.tmp = tempfile.mkdtemp(prefix="mc-test-")
        self.home = os.path.join(self.tmp, "Users", "budi")
        h = self.home
        write(h + "/Library/Caches/com.spotify.client/data.bin", 300_000)
        write(h + "/Library/Caches/com.apple.Safari/cache.db", 200_000)
        write(h + "/Library/Developer/Xcode/DerivedData/MyApp-abc/Build/x.o", 400_000)
        write(h + "/Library/Mobile Documents/com~apple~CloudDocs/thesis.pages", 150_000)
        write(h + "/Library/Application Support/MobileSync/Backup/123/Manifest.db", 400_000)
        write(h + "/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", 500_000)
        write(h + "/proyek/web/node_modules/react/index.js", 350_000)
        write(h + "/proyek/web/src/app.js", 1_000)
        write(h + "/Downloads/Zoom.dmg", 600_000)
        write(h + "/Pictures/Photos Library.photoslibrary/originals/IMG_1.mov", 700_000)
        write(h + "/Documents/skripsi.docx", 50_000)
        write(h + "/.Trash/lama.zip", 300_000)
        # hardlink: hanya boleh dihitung sekali
        os.link(h + "/Documents/skripsi.docx", h + "/Documents/skripsi-link.docx")

    def cleanup(self):
        shutil.rmtree(self.tmp, ignore_errors=True)


class RuleTests(unittest.TestCase):
    def setUp(self):
        self.m = RuleMatcher("/Users/budi")

    def rule(self, path):
        return self.m.match(path)

    def test_glob(self):
        self.assertEqual(glob_to_regex("**/node_modules"), "(?:.*/)?node_modules")

    def test_known_paths(self):
        cases = {
            "/Users/budi/Library/Caches": ("user-caches", AMAN),
            "/Users/budi/Library/Caches/com.spotify.client": ("user-caches-item", AMAN),
            "/Users/budi/Library/Caches/Homebrew": ("brew-cache", AMAN),
            "/Users/budi/Library/Developer/Xcode/DerivedData": ("xcode-deriveddata", AMAN),
            "/Users/budi/Library/Developer/Xcode/iOS DeviceSupport": ("xcode-devicesupport", AMAN),
            "/Users/budi/Library/Mobile Documents": ("icloud", JANGAN),
            "/Users/budi/Library/Application Support/MobileSync/Backup": ("ios-backup", HATI),
            "/Users/budi/code/app/node_modules": ("node-modules", AMAN),
            "/Users/budi/Downloads/Zoom.dmg": ("installer", AMAN),
            "/Users/budi/Downloads": ("downloads", PERIKSA),
            "/Users/budi/Pictures/Photos Library.photoslibrary": ("photos", JANGAN),
            "/System": ("system", JANGAN),
            "/Applications/Slack.app": ("app-bundle", HATI),
            "/Users/budi/Library/Application Support/Slack/Cache": ("app-caches", AMAN),
            "/Users/budi/.cache/huggingface": ("huggingface", HATI),
        }
        for path, (rid, safety) in cases.items():
            r = self.rule(path)
            self.assertIsNotNone(r, path)
            self.assertEqual((r.id, r.safety), (rid, safety), path)

    def test_case_insensitive(self):
        self.assertEqual(self.rule("/users/budi/library/caches").id, "user-caches")

    def test_unknown(self):
        self.assertIsNone(self.rule("/Users/budi/proyek/web/src"))

    def test_lock_inheritance(self):
        photos, _ = self.m.resolve("/Users/budi/Pictures/P.photoslibrary", None)
        # .mov biasanya "periksa", tapi di dalam Perpustakaan Foto tetap terkunci.
        r, inh = self.m.resolve("/Users/budi/Pictures/P.photoslibrary/originals/a.mov", photos, False)
        self.assertEqual(r.id, "photos")
        self.assertTrue(inh)
        icloud, _ = self.m.resolve("/Users/budi/Library/Mobile Documents", None)
        r, _ = self.m.resolve("/Users/budi/Library/Mobile Documents/x/node_modules", icloud, False)
        self.assertEqual(r.id, "icloud")

    def test_system_inherited(self):
        sysr, _ = self.m.resolve("/System", None)
        r, inh = self.m.resolve("/System/Library/CoreServices", sysr, False)
        self.assertEqual((r.id, inh), ("system", True))

    def test_non_inherit(self):
        lib, _ = self.m.resolve("/Users/budi/Library", None)
        r, _ = self.m.resolve("/Users/budi/Library/Foo", lib, False)
        self.assertIsNone(r)

    def test_protected(self):
        for p in ["/", "/System", "/Users/budi", "/Users/budi/Library", "/Users/budi/Documents",
                  "/Users/lain"]:
            self.assertTrue(self.m.is_protected(p), p)
        self.assertFalse(self.m.is_protected("/Users/budi/Library/Caches"))
        self.assertFalse(self.m.is_protected("/Users/budi/Documents/a.txt"))


class ScanTests(unittest.TestCase):
    def setUp(self):
        self.fh = FakeHome()
        self.scan = Scan(self.fh.home, RuleMatcher(self.fh.home))
        self.scan.run()

    def tearDown(self):
        self.fh.cleanup()

    def test_sizes_aggregate(self):
        root = self.scan.root
        self.assertEqual(self.scan.state, "done")
        self.assertEqual(root.size, sum(c.size for c in root.children) + root.own)
        caches = self.scan.index[self.fh.home + "/Library/Caches"]
        self.assertGreaterEqual(caches.size, 500_000)
        self.assertEqual(root.files, 12)  # 13 entri, 1 di antaranya hardlink ganda

    def test_recommendations(self):
        recs = self.scan.recommendations(min_size=1)
        by_rule = {}
        for r in recs:
            by_rule.setdefault(r["rule"].id, []).append(r["path"])
        h = self.fh.home
        self.assertIn(h + "/Library/Caches/com.spotify.client", by_rule["user-caches-item"])
        self.assertIn(h + "/Library/Developer/Xcode/DerivedData/MyApp-abc", by_rule["xcode-deriveddata"])
        self.assertIn(h + "/proyek/web/node_modules", by_rule["node-modules"])
        self.assertIn(h + "/Downloads/Zoom.dmg", by_rule["installer"])
        self.assertIn(h + "/Library/Application Support/MobileSync/Backup", by_rule["ios-backup"])
        all_paths = [p for v in by_rule.values() for p in v]
        self.assertFalse(any("Mobile Documents" in p for p in all_paths))
        self.assertFalse(any("photoslibrary" in p for p in all_paths))

    def test_categories(self):
        cats = self.scan.category_totals()
        self.assertGreater(cats["cache"], 0)
        self.assertGreater(cats["media"], 0)
        self.assertGreater(cats["cloud"], 0)


class ServerTests(unittest.TestCase):
    def setUp(self):
        self.fh = FakeHome()
        self.trash_home = os.path.join(self.fh.tmp, "xdg")
        os.environ["XDG_DATA_HOME"] = self.trash_home
        os.environ["MACCLEANER_TEST_TRASH"] = "1"
        self.httpd = make_server(0, home=self.fh.home)
        self.port = self.httpd.server_address[1]
        self.token = self.httpd.app_state.token
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()
        self.call("/api/scan", {"path": self.fh.home})
        self.httpd.app_state.scan.wait(30)

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()
        os.environ.pop("XDG_DATA_HOME", None)
        os.environ.pop("MACCLEANER_TEST_TRASH", None)
        self.fh.cleanup()

    def call(self, path, body=None, token=None, host=None):
        req = urllib.request.Request("http://127.0.0.1:%d%s" % (self.port, path))
        req.add_header("X-Token", self.token if token is None else token)
        if host:
            req.add_header("Host", host)
        if body is not None:
            req.data = json.dumps(body).encode()
            req.add_header("Content-Type", "application/json")
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())

    def test_token_required(self):
        with self.assertRaises(urllib.error.HTTPError) as cm:
            self.call("/api/status", token="salah")
        self.assertEqual(cm.exception.code, 403)

    def test_host_check(self):
        with self.assertRaises(urllib.error.HTTPError) as cm:
            self.call("/api/status", host="evil.example")
        self.assertEqual(cm.exception.code, 403)

    def test_index_has_token(self):
        with urllib.request.urlopen("http://127.0.0.1:%d/" % self.port) as r:
            self.assertIn(self.token, r.read().decode())

    def test_summary_node_recs(self):
        s = self.call("/api/summary")
        self.assertGreater(s["scanned"], 0)
        n = self.call("/api/node")
        names = [i["name"] for i in n["items"]]
        self.assertIn("Library", names)
        r = self.call("/api/recommendations")
        ids = {g["rule"]["id"] for g in r["groups"]}
        self.assertIn("node-modules", ids)
        lf = self.call("/api/largefiles")
        self.assertTrue(lf["items"])

    def test_trash_safe_item(self):
        target = self.fh.home + "/proyek/web/node_modules"
        before = self.call("/api/node")["node"]["size"]
        res = self.call("/api/trash", {"items": [{"path": target}]})
        self.assertEqual(res["errors"], [])
        self.assertFalse(os.path.exists(target))
        self.assertTrue(os.listdir(os.path.join(self.trash_home, "Trash", "files")))
        after = self.call("/api/node")["node"]["size"]
        self.assertLess(after, before)

    def test_trash_contents(self):
        target = self.fh.home + "/Library/Developer/Xcode/DerivedData"
        res = self.call("/api/trash", {"items": [{"path": target, "contents": True}]})
        self.assertEqual(res["errors"], [])
        self.assertTrue(os.path.isdir(target))
        self.assertEqual(os.listdir(target), [])

    def test_trash_refuses_dangerous(self):
        h = self.fh.home
        bad = [
            h + "/Library/Mobile Documents",                       # iCloud
            h + "/Pictures/Photos Library.photoslibrary/originals",  # Foto (terkunci)
            h + "/Library",                                         # dilindungi
            h + "/Documents",                                       # dilindungi
            h + "/Library/Containers/com.docker.docker",            # harus lewat docker prune
            h + "/Library/Application Support/MobileSync/Backup/123/Manifest.db",  # isi backup
            h + "/.Trash/lama.zip",                                 # sudah di Sampah
            "/etc",                                                 # di luar area pindai
            h + "/../budi/Library",                                 # trik path
        ]
        res = self.call("/api/trash", {"items": [{"path": p} for p in bad]})
        self.assertEqual(res["done"], [])
        self.assertEqual(len(res["errors"]), len(bad))
        for p in bad[:7]:
            self.assertTrue(os.path.exists(p), p)

    def test_whole_backup_allowed(self):
        # Satu backup utuh (anak langsung folder Backup) boleh dibuang.
        target = self.fh.home + "/Library/Application Support/MobileSync/Backup/123"
        res = self.call("/api/trash", {"items": [{"path": target}]})
        self.assertEqual(res["errors"], [])
        self.assertFalse(os.path.exists(target))

    def test_partof_flag_in_largefiles(self):
        items = {i["name"]: i for i in self.call("/api/largefiles")["items"]}
        self.assertFalse(items["Manifest.db"]["rule"]["deletable"])
        self.assertTrue(items["Manifest.db"]["rule"].get("partOf"))
        self.assertTrue(items["Zoom.dmg"]["rule"]["deletable"])


if __name__ == "__main__":
    unittest.main()
