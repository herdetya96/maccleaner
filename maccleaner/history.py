"""Riwayat pemindaian: ukuran, jumlah file & durasi per folder.

Dipakai untuk memperkirakan progres dan sisa waktu pada pemindaian berikutnya.
"""
from __future__ import annotations

import json
import os
import sys
import time
from typing import Dict, Optional

_FILE = "scan-history.json"


def data_dir() -> str:
    override = os.environ.get("MACCLEANER_DATA_DIR")
    if override:
        return override
    if sys.platform == "darwin":
        return os.path.expanduser("~/Library/Application Support/MacCleaner")
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "maccleaner")


def _load_all() -> Dict[str, dict]:
    try:
        with open(os.path.join(data_dir(), _FILE), encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def load(path: str) -> Optional[dict]:
    entry = _load_all().get(path)
    if isinstance(entry, dict) and entry.get("bytes"):
        return entry
    return None


def save(path: str, nbytes: int, files: int, duration: float) -> None:
    data = _load_all()
    data[path] = {"bytes": int(nbytes), "files": int(files),
                  "duration": round(float(duration), 2), "when": int(time.time())}
    # Simpan paling banyak 50 folder terakhir.
    if len(data) > 50:
        for k in sorted(data, key=lambda k: data[k].get("when", 0))[:-50]:
            data.pop(k, None)
    try:
        d = data_dir()
        os.makedirs(d, exist_ok=True)
        tmp = os.path.join(d, _FILE + ".tmp")
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(data, f)
        os.replace(tmp, os.path.join(d, _FILE))
    except OSError:
        pass


def fmt_duration(seconds: float) -> str:
    """45 dtk · 3 mnt 12 dtk · 1 jam 5 mnt"""
    s = int(round(max(0.0, seconds)))
    if s < 60:
        return "%d dtk" % s
    if s < 3600:
        m, sec = divmod(s, 60)
        return "%d mnt %d dtk" % (m, sec) if sec else "%d mnt" % m
    h, rest = divmod(s, 3600)
    m = rest // 60
    return "%d jam %d mnt" % (h, m) if m else "%d jam" % h


def fmt_eta(seconds: Optional[float]) -> str:
    """Sisa waktu dalam bahasa sehari-hari."""
    if seconds is None:
        return "Memperkirakan sisa waktu…"
    s = max(0.0, seconds)
    if s < 10:
        return "Hampir selesai…"
    if s < 60:
        return "Kurang dari 1 menit lagi"
    if s < 3600:
        return "Sekitar %d menit lagi" % max(1, int(round(s / 60.0)))
    h, rest = divmod(int(round(s / 60.0)), 60)
    return "Sekitar %d jam %d menit lagi" % (h, rest) if rest else "Sekitar %d jam lagi" % h


def prepare(scan, disks) -> None:
    """Isi perkiraan total untuk `scan` dan simpan riwayat setelah selesai."""
    h = load(scan.root_path)
    if h:
        scan.set_estimate("history", h.get("bytes", 0), h.get("files", 0), h.get("duration", 0))
    else:
        disk = next((d for d in disks if d.get("mount") == scan.root_path), None)
        if disk:
            scan.set_estimate("disk", disk.get("used", 0))
        else:
            scan.set_estimate("tree")

    def remember(s) -> None:
        if s.state == "done" and s.root is not None:
            save(s.root_path, s.root.size, s.root.files, s.finished - s.started)

    scan.on_done = remember
