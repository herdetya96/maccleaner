"""Pemindai disk: menghitung ukuran setiap folder dan mencatat file terbesar."""
from __future__ import annotations

import heapq
import os
import stat
import sys
import threading
import time
from typing import Dict, Iterator, List, Optional, Tuple

from .rules import AMAN, HATI, PERIKSA, Rule, RuleMatcher

TOP_PER_DIR = 12              # file terbesar yang diingat per folder
TOP_FILE_MIN = 256 * 1024     # hanya file >= 256 KB yang masuk daftar per folder
TOP_GLOBAL = 300              # jumlah file terbesar se-disk yang diingat


def file_size(st: os.stat_result) -> int:
    """Ukuran nyata di disk (blok terpakai), bukan ukuran logis."""
    blocks = getattr(st, "st_blocks", None)
    if blocks is not None:
        return blocks * 512
    return st.st_size


class Node:
    __slots__ = ("name", "path", "parent", "size", "own", "files", "children",
                 "top", "rule", "inh", "denied", "mtime", "depth", "share")

    def __init__(self, name: str, path: str, parent: Optional["Node"],
                 rule: Optional[Rule], inh: bool, mtime: float = 0.0):
        self.name = name
        self.path = path
        self.parent = parent
        self.size = 0          # total (termasuk sub-folder)
        self.own = 0           # file langsung di folder ini
        self.files = 0         # jumlah file (total, setelah agregasi)
        self.children: List[Node] = []
        self.top: List[Tuple[int, str, float]] = []   # (ukuran, nama, mtime)
        self.rule = rule
        self.inh = inh
        self.depth = 0         # kedalaman di bawah folder pemilik aturan
        self.share = 0.0       # "jatah" progres (untuk perkiraan tanpa riwayat)
        self.denied = False
        self.mtime = mtime

    def walk(self) -> Iterator["Node"]:
        stack = [self]
        while stack:
            n = stack.pop()
            yield n
            stack.extend(n.children)


class Scan:
    """Satu proses pemindaian (berjalan di thread terpisah)."""

    def __init__(self, root: str, matcher: RuleMatcher):
        self.root_path = os.path.abspath(os.path.expanduser(root))
        self.matcher = matcher
        self.state = "idle"          # idle | running | done | cancelled | error
        self.error = ""
        self.started = 0.0
        self.finished = 0.0
        self.files = 0
        self.dirs = 0
        self.bytes = 0
        self.current = ""
        self.denied: List[str] = []
        self.denied_count = 0
        self.root: Optional[Node] = None
        self.index: Dict[str, Node] = {}
        self.top_files: List[Tuple[int, str, float]] = []   # heap
        # Perkiraan total untuk progress bar & sisa waktu (diisi sebelum mulai).
        self.expected_bytes = 0
        self.expected_files = 0
        self.expected_duration = 0.0
        self.estimate_source = "tree"   # history | disk | tree
        self._done_share = 0.0
        self.on_done = None             # dipanggil setelah selesai (mis. simpan riwayat)
        self._best_fraction = 0.0
        self._cancel = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self.lock = threading.RLock()

    # ------------------------------------------------------------------
    def start(self) -> None:
        self.state = "running"
        self.started = time.time()
        self._thread = threading.Thread(target=self._run_safe, daemon=True)
        self._thread.start()

    def cancel(self) -> None:
        self._cancel.set()

    def wait(self, timeout: Optional[float] = None) -> None:
        if self._thread:
            self._thread.join(timeout)

    def run(self) -> None:
        """Pindai secara sinkron (untuk CLI / tes)."""
        self.state = "running"
        self.started = time.time()
        self._run_safe()

    def _run_safe(self) -> None:
        try:
            self._run()
            self.state = "cancelled" if self._cancel.is_set() else "done"
        except Exception as exc:  # pragma: no cover - dilaporkan ke UI
            self.state = "error"
            self.error = "%s: %s" % (type(exc).__name__, exc)
        finally:
            self.finished = time.time()
            self.current = ""
        if self.on_done is not None:
            try:
                self.on_done(self)
            except Exception:  # pragma: no cover - riwayat hanya bonus
                pass

    # ------------------------------------------------------------------
    def set_estimate(self, source: str, expected_bytes: int = 0, expected_files: int = 0,
                     expected_duration: float = 0.0) -> None:
        self.estimate_source = source
        self.expected_bytes = int(expected_bytes or 0)
        self.expected_files = int(expected_files or 0)
        self.expected_duration = float(expected_duration or 0.0)

    def fraction(self) -> float:
        """Perkiraan progres 0..1 (tidak pernah mundur)."""
        if self.state in ("done", "cancelled"):
            return 1.0
        tree = min(1.0, self._done_share)
        parts = []
        if self.expected_bytes > 0:
            parts.append(self.bytes / self.expected_bytes)
        if self.expected_files > 0:
            parts.append(self.files / self.expected_files)
        if self.estimate_source == "history" and parts:
            f = max(parts)
        elif self.estimate_source == "disk" and parts:
            # Sebagian ruang disk (sistem, snapshot) tidak terbaca → gabungkan dengan struktur folder.
            f = (max(parts) + tree) / 2
        else:
            f = tree
        f = max(0.0, min(0.99, f))
        self._best_fraction = max(self._best_fraction, f)
        return self._best_fraction

    def eta(self) -> Optional[float]:
        """Perkiraan sisa waktu (detik), None bila belum bisa diperkirakan."""
        if self.state != "running":
            return None
        elapsed = time.time() - self.started
        f = self.fraction()
        if f < 0.02 or elapsed < 3:
            if self.estimate_source == "history" and self.expected_duration > 0:
                return max(1.0, self.expected_duration - elapsed)
            return None
        by_rate = elapsed * (1 - f) / f
        if self.estimate_source == "history" and self.expected_duration > 0:
            by_hist = max(1.0, self.expected_duration - elapsed)
            return (by_rate + by_hist) / 2
        return by_rate

    def _skip_paths(self) -> set:
        skip = set()
        if sys.platform == "darwin":
            # Volume lain di container APFS yang sama & disk eksternal.
            skip |= {"/System/Volumes", "/Volumes", "/dev", "/net", "/home",
                     "/private/var/vm"}
        else:
            skip |= {"/proc", "/sys", "/dev", "/run"}
        return skip

    def _allowed_devs(self, root_st: os.stat_result) -> set:
        devs = {root_st.st_dev}
        if sys.platform == "darwin" and self.root_path == "/":
            # Sejak Catalina, data pengguna ada di volume "Data" yang
            # tersambung ke / lewat firmlink (/Users, /Applications, ...).
            try:
                devs.add(os.lstat("/System/Volumes/Data").st_dev)
            except OSError:
                pass
        return devs

    def _run(self) -> None:
        root_path = self.root_path
        matcher = self.matcher
        root_st = os.lstat(root_path)
        if not stat.S_ISDIR(root_st.st_mode):
            raise NotADirectoryError("Bukan folder: %s" % root_path)

        allowed = self._allowed_devs(root_st)
        skip = self._skip_paths()
        skip.discard(root_path)

        # Aturan untuk root: perhitungkan aturan milik leluhurnya.
        parent_rule: Optional[Rule] = None
        parent_inh = False
        ancestors = []
        p = os.path.dirname(root_path)
        while True:
            ancestors.append(p)
            np = os.path.dirname(p)
            if np == p:
                break
            p = np
        depth = 0
        for a in reversed(ancestors):
            if a == root_path:
                continue
            parent_rule, parent_inh = matcher.resolve(a, parent_rule, parent_inh)
            depth = depth + 1 if parent_inh else 0
        rule, inh = matcher.resolve(root_path, parent_rule, parent_inh)

        name = os.path.basename(root_path) or root_path
        root = Node(name, root_path, None, rule, inh, root_st.st_mtime)
        root.depth = depth + 1 if inh else 0
        root.share = 1.0
        self.root = root
        index = {root_path: root}
        self.index = index
        nodes: List[Node] = [root]
        stack: List[Node] = [root]
        seen_inodes = set()
        top_global = self.top_files
        cancel = self._cancel
        S_ISDIR = stat.S_ISDIR
        S_ISREG = stat.S_ISREG
        S_ISLNK = stat.S_ISLNK
        last_tick = 0.0
        files = 0
        total = 0

        while stack:
            if cancel.is_set():
                break
            node = stack.pop()
            try:
                it = os.scandir(node.path)
            except PermissionError:
                node.denied = True
                self.denied_count += 1
                if len(self.denied) < 200:
                    self.denied.append(node.path)
                self._done_share += node.share
                continue
            except OSError:
                self._done_share += node.share
                continue

            prule = node.rule
            pinh = node.inh
            top = node.top
            first_child = len(node.children)
            with it:
                for entry in it:
                    try:
                        st = entry.stat(follow_symlinks=False)
                    except OSError:
                        continue
                    mode = st.st_mode
                    if S_ISDIR(mode):
                        path = entry.path
                        if st.st_dev not in allowed or path in skip:
                            continue
                        crule, cinh = matcher.resolve(path, prule, pinh)
                        child = Node(entry.name, path, node, crule, cinh, st.st_mtime)
                        if cinh:
                            child.depth = node.depth + 1
                        node.children.append(child)
                        nodes.append(child)
                        stack.append(child)
                        index[path] = child
                    elif S_ISREG(mode) or S_ISLNK(mode):
                        if st.st_nlink > 1 and S_ISREG(mode):
                            key = (st.st_dev, st.st_ino)
                            if key in seen_inodes:
                                continue
                            seen_inodes.add(key)
                        size = file_size(st)
                        node.own += size
                        node.files += 1
                        files += 1
                        total += size
                        if size >= TOP_FILE_MIN:
                            item = (size, entry.name, st.st_mtime)
                            if len(top) < TOP_PER_DIR:
                                top.append(item)
                            else:
                                mi = min(range(len(top)), key=lambda i: top[i][0])
                                if size > top[mi][0]:
                                    top[mi] = item
                            gitem = (size, entry.path, st.st_mtime)
                            if len(top_global) < TOP_GLOBAL:
                                heapq.heappush(top_global, gitem)
                            elif size > top_global[0][0]:
                                heapq.heapreplace(top_global, gitem)

            # Bagi jatah progres folder ini rata ke sub-foldernya.
            kids = node.children[first_child:]
            if kids:
                part = node.share / len(kids)
                for c in kids:
                    c.share = part
            else:
                self._done_share += node.share

            now = time.monotonic()
            if now - last_tick > 0.1:
                last_tick = now
                self.files = files
                self.bytes = total
                self.dirs = len(nodes)
                self.current = node.path

        self.files = files
        self.bytes = total
        self.dirs = len(nodes)

        # Agregasi ukuran dari bawah ke atas (anak selalu dibuat setelah induknya).
        for n in nodes:
            n.size = n.own
        for n in reversed(nodes):
            if n.parent is not None:
                n.parent.size += n.size
                n.parent.files += n.files
        for n in nodes:
            n.children.sort(key=lambda c: c.size, reverse=True)
            n.top.sort(reverse=True)

    # ------------------------------------------------------------------
    # Kueri hasil
    # ------------------------------------------------------------------
    def file_rule(self, path: str, parent: Optional[Node]):
        """(rule, inherited, depth) untuk sebuah file."""
        prule = parent.rule if parent else None
        pinh = parent.inh if parent else False
        rule, inh = self.matcher.resolve(path, prule, pinh)
        depth = (parent.depth + 1) if (inh and parent is not None) else 0
        return rule, inh, depth

    def largest_files(self, limit: int = 100) -> List[Tuple[int, str, float]]:
        with self.lock:
            return sorted(self.top_files, reverse=True)[:limit]

    def category_totals(self) -> Dict[str, int]:
        totals: Dict[str, int] = {}
        if not self.root:
            return totals
        with self.lock:
            for n in self.root.walk():
                cat = n.rule.category if n.rule else "other"
                totals[cat] = totals.get(cat, 0) + n.own
        return totals

    def recommendations(self, min_size: int = 100 * 1024) -> List[dict]:
        """Kandidat pembersihan: [{rule, path, size, kind}]

        kind = "trash"  -> bisa dibuang langsung dari aplikasi
               "manual" -> perlu dibersihkan dari aplikasi/perintah terkait
        """
        out: List[dict] = []
        if not self.root:
            return out
        covered: List[str] = []

        def add(node: Node, rule: Rule, kind: str) -> None:
            out.append({"rule": rule, "path": node.path, "size": node.size,
                        "files": node.files, "mtime": node.mtime, "kind": kind,
                        "isDir": True})
            covered.append(node.path)

        def visit(node: Node) -> None:
            r = node.rule
            own = r is not None and not node.inh
            if own and r.deletable and r.safety in (AMAN, HATI):
                if r.mode == "contents":
                    for c in node.children:
                        if c.inh and c.rule is r:
                            if c.size >= min_size:
                                add(c, r, "trash")
                        else:
                            visit(c)
                    return
                if node.size >= min_size:
                    add(node, r, "trash")
                return
            if own and not r.deletable and r.safety in (AMAN, HATI, PERIKSA) \
                    and (r.how or r.command) and node.size >= 50 * 1000 * 1000 \
                    and r.id not in ("user-library", "home", "users", "system-library"):
                add(node, r, "manual")
                return
            for c in node.children:
                visit(c)

        with self.lock:
            visit(self.root)
            # File besar yang dikenali (installer, file update iOS, ...).
            for size, path, mtime in sorted(self.top_files, reverse=True):
                if any(path.startswith(c + "/") for c in covered):
                    continue
                parent = self.index.get(os.path.dirname(path))
                rule, inh, _ = self.file_rule(path, parent)
                if rule is None or inh or not rule.deletable:
                    continue
                if rule.safety not in (AMAN, HATI) and rule.category != "installer":
                    continue
                out.append({"rule": rule, "path": path, "size": size, "files": 1,
                            "mtime": mtime, "kind": "trash", "isDir": False})
            # File besar di Unduhan yang sudah lama tidak disentuh (> 90 hari).
            dl = os.path.join(self.matcher.home, "Downloads")
            dl_rule = None
            limit = time.time() - 90 * 86400
            known = {o["path"] for o in out}
            for size, path, mtime in sorted(self.top_files, reverse=True):
                if not path.startswith(dl + "/") or path in known or mtime > limit:
                    continue
                if size < 20 * 1024 * 1024:
                    continue
                if dl_rule is None:
                    dl_rule = OLD_DOWNLOADS_RULE
                out.append({"rule": dl_rule, "path": path, "size": size, "files": 1,
                            "mtime": mtime, "kind": "trash", "isDir": False})
        return out

    # ------------------------------------------------------------------
    def remove(self, path: str) -> int:
        """Keluarkan path yang sudah dibuang dari hasil pindai.
        Mengembalikan jumlah byte yang dikurangi."""
        with self.lock:
            node = self.index.get(path)
            if node is not None:
                size = node.size
                files = node.files
                parent = node.parent
                if parent is not None:
                    parent.children = [c for c in parent.children if c is not node]
                for n in node.walk():
                    self.index.pop(n.path, None)
                self.top_files = [t for t in self.top_files
                                  if not (t[1] == path or t[1].startswith(path + "/"))]
                heapq.heapify(self.top_files)
            else:
                parent = self.index.get(os.path.dirname(path))
                size = 0
                files = 1
                for t in self.top_files:
                    if t[1] == path:
                        size = t[0]
                        break
                if parent is not None:
                    name = os.path.basename(path)
                    for t in parent.top:
                        if t[1] == name:
                            size = size or t[0]
                    parent.top = [t for t in parent.top if t[1] != name]
                    parent.own = max(0, parent.own - size)
                self.top_files = [t for t in self.top_files if t[1] != path]
                heapq.heapify(self.top_files)
            p = parent
            while p is not None:
                p.size = max(0, p.size - size)
                p.files = max(0, p.files - files)
                p = p.parent
            self.bytes = max(0, self.bytes - size)
            if parent is not None:
                parent.children.sort(key=lambda c: c.size, reverse=True)
            return size

    def known_file(self, path: str) -> Optional[Tuple[int, float]]:
        """(ukuran, mtime) bila path adalah file yang tercatat di hasil pindai."""
        with self.lock:
            for t in self.top_files:
                if t[1] == path:
                    return t[0], t[2]
            parent = self.index.get(os.path.dirname(path))
            if parent is not None:
                name = os.path.basename(path)
                for t in parent.top:
                    if t[1] == name:
                        return t[0], t[2]
        return None


OLD_DOWNLOADS_RULE = Rule(
    "old-downloads", [], "File lama di Unduhan", "downloads", PERIKSA,
    "File besar di folder Unduhan yang tidak diubah lebih dari 90 hari.",
    "File hilang (masih bisa dikembalikan dari Sampah sebelum dikosongkan).",
    "Periksa satu per satu; buang yang sudah tidak diperlukan.")
