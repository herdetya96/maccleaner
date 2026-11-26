"""Informasi disk/volume yang terpasang."""
from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
from typing import Dict, List, Optional


def _run(cmd: List[str], timeout: float = 10) -> Optional[bytes]:
    try:
        return subprocess.run(cmd, capture_output=True, timeout=timeout, check=True).stdout
    except (OSError, subprocess.SubprocessError):
        return None


def _df_mounts() -> List[Dict[str, str]]:
    """Daftar mount dari `df -kP` (portabel di macOS & Linux)."""
    out = _run(["df", "-kP"])
    mounts: List[Dict[str, str]] = []
    if not out:
        return mounts
    lines = out.decode("utf-8", "replace").splitlines()[1:]
    for line in lines:
        parts = line.split()
        if len(parts) < 6:
            continue
        # Nama mount bisa mengandung spasi: semua kolom setelah kolom ke-5.
        device = parts[0]
        mount = " ".join(parts[5:])
        mounts.append({"device": device, "mount": mount})
    return mounts


def _mac_volume_info(mount: str) -> Dict:
    out = _run(["diskutil", "info", "-plist", mount])
    if not out:
        return {}
    try:
        return plistlib.loads(out)
    except Exception:
        return {}


def _usage(mount: str) -> Optional[Dict[str, int]]:
    try:
        u = shutil.disk_usage(mount)
    except OSError:
        return None
    return {"total": u.total, "used": u.total - u.free, "free": u.free}


def list_disks(home: Optional[str] = None) -> List[Dict]:
    disks: List[Dict] = []
    seen = set()
    home = home or os.path.expanduser("~")

    if sys.platform == "darwin":
        candidates = ["/"]
        for m in _df_mounts():
            mp = m["mount"]
            if m["device"].startswith("/dev/") and mp.startswith("/Volumes/"):
                candidates.append(mp)
        for mp in candidates:
            info = _mac_volume_info(mp)
            usage = _usage(mp)
            if usage is None:
                continue
            total = info.get("APFSContainerSize") or info.get("TotalSize") or usage["total"]
            free = info.get("APFSContainerFree")
            if free is None:
                free = info.get("FreeSpace") or usage["free"]
            name = info.get("VolumeName") or (os.path.basename(mp) if mp != "/" else "Macintosh HD")
            key = (info.get("APFSContainerReference") or mp)
            if key in seen:
                continue
            seen.add(key)
            disks.append(_disk(name, mp, total, total - free, free,
                               internal=bool(info.get("Internal", mp == "/")),
                               fs=info.get("FilesystemName") or info.get("FilesystemType", ""),
                               is_root=(mp == "/"),
                               scan_paths=_scan_paths(mp, home)))
    else:
        mounts = [m for m in _df_mounts()
                  if m["device"].startswith("/dev/") and not m["mount"].startswith(("/boot", "/snap"))]
        if not any(m["mount"] == "/" for m in mounts):
            mounts.insert(0, {"device": "", "mount": "/"})
        for m in mounts:
            mp = m["mount"]
            usage = _usage(mp)
            if usage is None:
                continue
            try:
                dev = os.stat(mp).st_dev
            except OSError:
                continue
            if dev in seen:
                continue
            seen.add(dev)
            name = "Disk sistem" if mp == "/" else os.path.basename(mp) or mp
            disks.append(_disk(name, mp, usage["total"], usage["used"], usage["free"],
                               internal=mp == "/", fs="", is_root=(mp == "/"),
                               scan_paths=_scan_paths(mp, home)))
    return disks


def _scan_paths(mount: str, home: str) -> List[Dict[str, str]]:
    paths = []
    if mount == "/":
        paths.append({"label": "Folder rumah (%s)" % os.path.basename(home), "path": home})
        paths.append({"label": "Seluruh disk", "path": "/"})
    else:
        paths.append({"label": "Seluruh volume", "path": mount})
    return paths


def _disk(name, mount, total, used, free, internal, fs, is_root, scan_paths) -> Dict:
    total = int(total or 0)
    used = int(max(0, used or 0))
    free = int(max(0, free or 0))
    pct = (used / total * 100.0) if total else 0.0
    if pct >= 95:
        level, msg = "kritis", "Disk hampir penuh! macOS bisa melambat, gagal update, atau aplikasi crash."
    elif pct >= 85:
        level, msg = "tinggi", "Disk mulai penuh. Sisakan minimal 10–15% agar macOS lancar (swap, update, cache)."
    elif pct >= 70:
        level, msg = "sedang", "Masih aman, tapi ada baiknya mulai bersih-bersih."
    else:
        level, msg = "aman", "Ruang disk masih lega."
    return {
        "name": name, "mount": mount, "total": total, "used": used, "free": free,
        "percent": round(pct, 1), "level": level, "message": msg,
        "internal": internal, "fs": fs, "isRoot": is_root, "scanPaths": scan_paths,
    }
