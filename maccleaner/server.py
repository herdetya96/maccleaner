"""Server HTTP lokal yang melayani antarmuka web & API JSON.

Hanya mendengarkan di 127.0.0.1 dan setiap panggilan API wajib membawa
token acak (mencegah situs web lain memicu penghapusan lewat browser).
"""
from __future__ import annotations

import json
import os
import secrets
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, List, Optional
from urllib.parse import parse_qs, urlparse

from . import __version__
from .disks import list_disks
from .rules import (AMAN, HATI, JANGAN, PERIKSA, CATEGORIES, RuleMatcher, can_delete,
                    rule_info)
from .scanner import Scan
from . import history
from . import trash as trashmod

WEB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "web")
STATIC = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/app.js": ("app.js", "application/javascript; charset=utf-8"),
    "/style.css": ("style.css", "text/css; charset=utf-8"),
}

GB = 1000 ** 3


def human(n: float) -> str:
    """Satuan desimal (1 GB = 1000³ byte), sama seperti Finder di macOS."""
    n = float(n)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if abs(n) < 999.95 or unit == "TB":
            if unit == "B":
                return "%d %s" % (n, unit)
            return ("%.1f %s" % (n, unit)).replace(".", ",")
        n /= 1000.0
    return "%.1f TB" % n


class AppState:
    def __init__(self, home: Optional[str] = None):
        self.home = os.path.abspath(home or os.path.expanduser("~"))
        self.matcher = RuleMatcher(self.home)
        self.token = secrets.token_urlsafe(24)
        self.scan: Optional[Scan] = None
        self.lock = threading.Lock()
        self.last_seen = time.time()   # panggilan API terakhir dari browser

    # ------------------------------------------------------------------
    def start_scan(self, path: str) -> Scan:
        path = os.path.abspath(os.path.expanduser(path or self.home))
        if not os.path.isdir(path):
            raise ValueError("Folder tidak ditemukan: %s" % path)
        with self.lock:
            if self.scan and self.scan.state == "running":
                self.scan.cancel()
                self.scan.wait(5)
            self.scan = Scan(path, self.matcher)
            history.prepare(self.scan, list_disks(self.home))
            self.scan.start()
            return self.scan

    def require_scan(self) -> Scan:
        s = self.scan
        if s is None or s.root is None or s.state == "running":
            raise LookupError("Belum ada hasil pemindaian. Mulai pindai dulu.")
        return s

    # ------------------------------------------------------------------
    def status(self) -> Dict:
        s = self.scan
        if s is None:
            return {"state": "idle"}
        end = s.finished or time.time()
        return {
            "state": s.state, "error": s.error, "root": s.root_path,
            "display": self.matcher.display(s.root_path),
            "files": s.files, "dirs": s.dirs, "bytes": s.bytes,
            "current": self.matcher.display(s.current) if s.current else "",
            "elapsed": round(end - s.started, 1) if s.started else 0,
            "denied": s.denied_count,
            "fraction": round(s.fraction(), 4),
            "eta": s.eta(),
            "estimate": s.estimate_source,
        }

    def _item(self, path: str, name: str, size: int, files: int, is_dir: bool,
              mtime: float, rule, inh: bool, parent_size: int, denied: bool = False,
              depth: int = 0) -> Dict:
        return {
            "name": name, "path": path, "display": self.matcher.display(path),
            "size": size, "files": files, "isDir": is_dir, "mtime": mtime,
            "denied": denied,
            "pct": round(size / parent_size * 100, 1) if parent_size else 0,
            "rule": rule_info(rule, inh, depth),
            "protected": self.matcher.is_protected(path),
        }

    def node(self, path: Optional[str]) -> Dict:
        s = self.require_scan()
        path = os.path.abspath(path) if path else s.root_path
        with s.lock:
            n = s.index.get(path)
            if n is None:
                raise LookupError("Folder tidak ada di hasil pindai: %s" % path)
            items: List[Dict] = []
            shown = n.children[:300]
            for c in shown:
                items.append(self._item(c.path, c.name, c.size, c.files, True, c.mtime,
                                        c.rule, c.inh, n.size, c.denied, c.depth))
            listed = 0
            for size, name, mtime in n.top:
                fpath = os.path.join(n.path, name)
                rule, inh, depth = s.file_rule(fpath, n)
                items.append(self._item(fpath, name, size, 1, False, mtime, rule, inh, n.size,
                                        depth=depth))
                listed += size
            hidden_dirs = n.children[300:]
            other = n.own - listed + sum(c.size for c in hidden_dirs)
            other_count = n.files - sum(c.files for c in shown) - len(n.top)
            if other > 0 and other_count > 0:
                label = "%d file kecil lainnya" % other_count
                if hidden_dirs:
                    label += " (termasuk %d folder kecil)" % len(hidden_dirs)
                items.append({
                    "name": label, "path": None,
                    "display": "", "size": other, "files": other_count, "isDir": False,
                    "mtime": 0, "other": True,
                    "pct": round(other / n.size * 100, 1) if n.size else 0,
                    "rule": rule_info(n.rule, True), "protected": True,
                })
            items.sort(key=lambda x: x["size"], reverse=True)
            crumbs = []
            p = n
            while p is not None:
                crumbs.append({"name": self.matcher.display(p.path) if p.parent is None else p.name,
                               "path": p.path})
                p = p.parent
            crumbs.reverse()
            me = self._item(n.path, n.name, n.size, n.files, True, n.mtime, n.rule, n.inh,
                            n.parent.size if n.parent else n.size, n.denied, n.depth)
            return {"node": me, "items": items, "crumbs": crumbs}

    # ------------------------------------------------------------------
    def _disk_for(self, path: str) -> Optional[Dict]:
        best = None
        for d in list_disks(self.home):
            m = d["mount"]
            if path == m or path.startswith(m.rstrip("/") + "/") or m == "/":
                if best is None or len(m) > len(best["mount"]):
                    best = d
        return best

    def summary(self) -> Dict:
        s = self.require_scan()
        totals = s.category_totals()
        cats = [{"id": k, "label": CATEGORIES.get(k, k), "size": v}
                for k, v in totals.items() if v > 0]
        cats.sort(key=lambda c: c["size"], reverse=True)
        scanned = s.root.size if s.root else 0
        disk = self._disk_for(s.root_path)
        whole_disk = disk is not None and s.root_path == disk["mount"]
        unscanned = max(0, disk["used"] - scanned) if disk else 0

        recs = self.recommendations()
        safe_total = sum(g["total"] for g in recs["groups"]
                         if g["rule"]["safety"] == AMAN and g["kind"] == "trash")
        caution_total = sum(g["total"] for g in recs["groups"]
                            if g["rule"]["safety"] == HATI)

        insights: List[Dict] = []
        if disk:
            insights.append({"level": disk["level"], "text": "%s terpakai %.0f%% (%s dari %s). %s" % (
                disk["name"], disk["percent"], human(disk["used"]), human(disk["total"]),
                disk["message"])})
        if cats:
            top = ", ".join("%s (%s)" % (c["label"], human(c["size"])) for c in cats[:3])
            insights.append({"level": "info",
                             "text": "Pemakai ruang terbesar di %s: %s." % (
                                 self.matcher.display(s.root_path), top)})
        biggest = [g for g in recs["groups"] if g["kind"] == "trash"][:3]
        if safe_total:
            insights.append({"level": "aman", "text":
                             "Sekitar %s bisa dikosongkan dengan aman (cache, build, installer, dll)."
                             % human(safe_total)})
        for g in biggest:
            if g["total"] >= 500 * 1024 * 1024:
                insights.append({"level": g["rule"]["safety"], "text": "%s: %s di %d lokasi — %s" % (
                    g["rule"]["title"], human(g["total"]), len(g["items"]),
                    g["rule"]["safetyLabel"].lower())})
        if caution_total >= GB:
            insights.append({"level": "hati", "text":
                             "%s lainnya bisa dikosongkan tapi perlu dipertimbangkan (backup, simulator, VM, dll)."
                             % human(caution_total)})
        if disk and whole_disk and unscanned >= 2 * GB:
            insights.append({"level": "info", "text":
                             "%s tidak terlihat oleh pemindaian: biasanya data sistem macOS, snapshot "
                             "Time Machine lokal, swap, atau folder yang aksesnya ditolak." % human(unscanned)})
        elif disk and not whole_disk and unscanned >= 5 * GB:
            insights.append({"level": "info", "text":
                             "%s lainnya berada di luar %s (aplikasi, sistem, pengguna lain). "
                             "Pindai \"Seluruh disk\" untuk melihat semuanya." % (
                                 human(unscanned), self.matcher.display(s.root_path))})
        if s.denied_count:
            insights.append({"level": "hati", "text":
                             "%d folder tidak bisa dibaca karena izin. Di macOS, beri \"Akses Disk Penuh\" "
                             "ke Terminal: Pengaturan Sistem → Privasi & Keamanan → Akses Disk Penuh."
                             % s.denied_count})

        return {
            "root": s.root_path, "display": self.matcher.display(s.root_path),
            "scanned": scanned, "files": s.root.files if s.root else 0, "dirs": s.dirs,
            "elapsed": round((s.finished or time.time()) - s.started, 1),
            "categories": cats, "disk": disk, "wholeDisk": whole_disk,
            "unscanned": unscanned, "safeTotal": safe_total, "cautionTotal": caution_total,
            "denied": s.denied_count,
            "deniedSample": [self.matcher.display(p) for p in s.denied[:20]],
            "insights": insights,
        }

    def recommendations(self) -> Dict:
        s = self.require_scan()
        groups: Dict[str, Dict] = {}
        for rec in s.recommendations():
            rule = rec["rule"]
            key = "%s:%s" % (rule.id, rec["kind"])
            g = groups.get(key)
            if g is None:
                info = rule_info(rule, False)
                g = groups[key] = {"id": key, "rule": info, "kind": rec["kind"],
                                   "total": 0, "items": []}
            g["total"] += rec["size"]
            g["items"].append({
                "path": rec["path"], "display": self.matcher.display(rec["path"]),
                "size": rec["size"], "files": rec["files"], "mtime": rec["mtime"],
                "isDir": rec["isDir"],
            })
        # Sampah: selalu tampilkan bila berisi.
        trash_group = None
        for k in list(groups):
            if groups[k]["rule"]["id"] == "trash":
                trash_group = groups.pop(k)
        # Ukur langsung (Sampah berubah setelah membuang file); hasil pindai
        # dipakai bila folder Sampah tidak bisa dibaca karena izin.
        try:
            tsize = trashmod.trash_size()
        except OSError:
            tsize = 0
        if not tsize and trash_group:
            tsize = trash_group["total"]
        out = list(groups.values())
        order = {AMAN: 0, HATI: 1, PERIKSA: 2, JANGAN: 3}
        for g in out:
            g["items"].sort(key=lambda i: i["size"], reverse=True)
        out.sort(key=lambda g: (g["kind"] != "trash", order.get(g["rule"]["safety"], 4), -g["total"]))
        return {"groups": out, "trash": tsize}

    def largefiles(self, limit: int = 150) -> Dict:
        s = self.require_scan()
        items = []
        for size, path, mtime in s.largest_files(limit):
            parent = s.index.get(os.path.dirname(path))
            rule, inh, depth = s.file_rule(path, parent)
            items.append(self._item(path, os.path.basename(path), size, 1, False, mtime,
                                    rule, inh, 0, depth=depth))
        return {"items": items}

    # ------------------------------------------------------------------
    def _check_path(self, s: Scan, path: str):
        """Validasi sebelum dibuang. Mengembalikan (rule, inherited) atau raise ValueError."""
        if not path or not os.path.isabs(path):
            raise ValueError("Path tidak valid.")
        path = os.path.normpath(path)
        root = s.root_path.rstrip("/")
        if not (path.startswith(root + "/") or (root == "" and path != "/")):
            raise ValueError("Di luar folder yang dipindai.")
        if self.matcher.is_protected(path):
            raise ValueError("Folder penting sistem/pengguna — dilindungi.")
        if not os.path.lexists(path):
            raise ValueError("Sudah tidak ada.")
        node = s.index.get(path)
        if node is not None:
            rule, inh, depth = node.rule, node.inh, node.depth
        elif s.known_file(path) is not None or os.path.dirname(path) in s.index:
            rule, inh, depth = s.file_rule(path, s.index.get(os.path.dirname(path)))
        else:
            raise ValueError("Tidak ada di hasil pindai.")
        if rule is not None:
            if rule.safety == JANGAN:
                raise ValueError("%s — jangan dihapus. %s" % (rule.title, rule.how))
            if not rule.deletable:
                msg = "%s harus dibersihkan lewat caranya sendiri: %s %s" % (
                    rule.title, rule.how, rule.command)
                raise ValueError(msg.strip())
            if not can_delete(rule, depth):
                raise ValueError("Bagian dalam dari \"%s\" — buang seluruh foldernya, "
                                 "bukan file di dalamnya." % rule.title)
        return rule, inh

    def trash(self, items: List[Dict]) -> Dict:
        s = self.require_scan()
        targets: List[str] = []
        errors: List[Dict] = []
        cleared_dirs: List[str] = []
        for it in items:
            path = os.path.normpath(str(it.get("path") or ""))
            try:
                self._check_path(s, path)
            except ValueError as e:
                errors.append({"path": path, "display": self.matcher.display(path), "error": str(e)})
                continue
            if it.get("contents") and os.path.isdir(path) and not os.path.islink(path):
                try:
                    names = os.listdir(path)
                except OSError as e:
                    errors.append({"path": path, "display": self.matcher.display(path),
                                   "error": trashmod._friendly(e)})
                    continue
                node = s.index.get(path)
                for name in names:
                    child = os.path.join(path, name)
                    crule, cinh = self.matcher.resolve(child, node.rule if node else None,
                                                       node.inh if node else False)
                    cdepth = (node.depth + 1) if (cinh and node is not None) else 0
                    if crule is not None and (crule.safety == JANGAN
                                              or not can_delete(crule, cdepth)):
                        continue
                    targets.append(child)
                cleared_dirs.append(path)
            else:
                targets.append(path)

        freed = 0
        done: List[Dict] = []
        for path, ok, msg in trashmod.move_to_trash(targets):
            if ok:
                freed += s.remove(path)
                done.append({"path": path, "display": self.matcher.display(path)})
            else:
                errors.append({"path": path, "display": self.matcher.display(path), "error": msg})
        for d in cleared_dirs:
            freed += self._clear_own(s, d)
        return {"done": done, "errors": errors, "freed": freed,
                "note": "File ada di Sampah. Ruang disk baru benar-benar kosong setelah Sampah dikosongkan."}

    def _clear_own(self, s: Scan, path: str) -> int:
        """Setelah isi folder dibuang: hitung ulang file yang tersisa langsung di folder itu."""
        with s.lock:
            node = s.index.get(path)
            if node is None:
                return 0
            remaining = 0
            count = 0
            try:
                for e in os.scandir(path):
                    try:
                        st = e.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    if not e.is_dir(follow_symlinks=False):
                        from .scanner import file_size
                        remaining += file_size(st)
                        count += 1
            except OSError:
                return 0
            diff = max(0, node.own - remaining)
            node.own = remaining
            node.top = [t for t in node.top if os.path.lexists(os.path.join(path, t[1]))]
            p = node
            while p is not None:
                p.size = max(0, p.size - diff)
                p = p.parent
            return diff


class Handler(BaseHTTPRequestHandler):
    server_version = "MacCleaner/" + __version__
    state: AppState = None  # type: ignore[assignment]

    def log_message(self, fmt, *args):  # tenang
        if os.environ.get("MACCLEANER_DEBUG"):
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

    # ------------------------------------------------------------------
    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code: int = 200) -> None:
        self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"),
                   "application/json; charset=utf-8")

    def _host_ok(self) -> bool:
        host = (self.headers.get("Host") or "").split(":")[0].strip("[]").lower()
        return host in ("127.0.0.1", "localhost", "::1")

    def _auth_ok(self) -> bool:
        given = (self.headers.get("X-Token") or "").encode("utf-8", "replace")
        return secrets.compare_digest(given, self.state.token.encode())

    def _body(self) -> Dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > 5 * 1024 * 1024:
            return {}
        try:
            return json.loads(self.rfile.read(length).decode("utf-8"))
        except ValueError:
            return {}

    # ------------------------------------------------------------------
    def do_GET(self):
        self._dispatch("GET")

    def do_POST(self):
        self._dispatch("POST")

    def _dispatch(self, method: str) -> None:
        if not self._host_ok():
            self._send(403, b"Forbidden", "text/plain")
            return
        url = urlparse(self.path)
        if method == "GET" and url.path in STATIC:
            fname, ctype = STATIC[url.path]
            with open(os.path.join(WEB_DIR, fname), "rb") as f:
                data = f.read()
            if fname == "index.html":
                data = data.replace(b"{{TOKEN}}", self.state.token.encode())
                data = data.replace(b"{{VERSION}}", __version__.encode())
            self._send(200, data, ctype)
            return
        if not url.path.startswith("/api/"):
            self._send(404, b"Not found", "text/plain")
            return
        if not self._auth_ok():
            self._json({"error": "Token tidak valid. Muat ulang halaman."}, 403)
            return
        q = {k: v[0] for k, v in parse_qs(url.query).items()}
        st = self.state
        route = (method, url.path)
        st.last_seen = time.time()
        try:
            if route == ("GET", "/api/info"):
                self._json({"version": __version__, "home": st.home,
                            "platform": sys.platform, "status": st.status()})
            elif route == ("GET", "/api/disks"):
                self._json({"disks": list_disks(st.home)})
            elif route == ("GET", "/api/ping"):
                self._json({"ok": True})
            elif route == ("GET", "/api/status"):
                self._json(st.status())
            elif route == ("POST", "/api/scan"):
                body = self._body()
                st.start_scan(body.get("path") or st.home)
                self._json(st.status())
            elif route == ("POST", "/api/cancel"):
                if st.scan:
                    st.scan.cancel()
                self._json({"ok": True})
            elif route == ("GET", "/api/node"):
                self._json(st.node(q.get("path")))
            elif route == ("GET", "/api/summary"):
                self._json(st.summary())
            elif route == ("GET", "/api/recommendations"):
                self._json(st.recommendations())
            elif route == ("GET", "/api/largefiles"):
                self._json(st.largefiles())
            elif route == ("POST", "/api/trash"):
                body = self._body()
                self._json(st.trash(body.get("items") or []))
            elif route == ("POST", "/api/empty-trash"):
                ok, msg = trashmod.empty_trash()
                self._json({"ok": ok, "message": msg})
            elif route == ("POST", "/api/reveal"):
                body = self._body()
                path = body.get("path") or ""
                ok = os.path.lexists(path) and trashmod.reveal(path)
                self._json({"ok": bool(ok)})
            else:
                self._json({"error": "Tidak ditemukan"}, 404)
        except LookupError as e:
            self._json({"error": str(e)}, 409)
        except ValueError as e:
            self._json({"error": str(e)}, 400)
        except Exception as e:  # pragma: no cover
            self._json({"error": "%s: %s" % (type(e).__name__, e)}, 500)


def make_server(port: int = 0, home: Optional[str] = None) -> ThreadingHTTPServer:
    state = AppState(home)
    handler = type("BoundHandler", (Handler,), {"state": state})
    httpd = ThreadingHTTPServer(("127.0.0.1", port), handler)
    httpd.daemon_threads = True
    httpd.app_state = state  # type: ignore[attr-defined]
    return httpd


def serve(port: int = 8765, open_browser: bool = True, auto_exit: bool = False) -> None:
    try:
        httpd = make_server(port)
    except OSError:
        httpd = make_server(0)  # port terpakai → pilih port bebas
    url = "http://127.0.0.1:%d/" % httpd.server_address[1]
    print("MacCleaner berjalan di %s" % url)
    print("Tekan Ctrl+C untuk berhenti.")
    if open_browser:
        import webbrowser
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    if auto_exit:
        # Dipakai saat dijalankan sebagai MacCleaner.app (tanpa Terminal):
        # berhenti sendiri ±2 menit setelah tab browser ditutup.
        state: AppState = httpd.app_state  # type: ignore[attr-defined]

        def watchdog() -> None:
            while True:
                time.sleep(15)
                if time.time() - state.last_seen > 120 and \
                        not (state.scan and state.scan.state == "running"):
                    httpd.shutdown()
                    return

        threading.Thread(target=watchdog, daemon=True).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nSelesai.")
    finally:
        httpd.server_close()
