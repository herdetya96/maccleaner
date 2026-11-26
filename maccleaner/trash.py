"""Memindahkan file ke Sampah (bukan hapus permanen) dan mengosongkan Sampah."""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import time
from typing import List, Tuple
from urllib.parse import quote

_FINDER_DELETE = """
on run argv
    set itemList to {}
    repeat with p in argv
        set end of itemList to (POSIX file (contents of p))
    end repeat
    tell application "Finder" to delete itemList
end run
"""


def _unique(dirpath: str, name: str) -> str:
    target = os.path.join(dirpath, name)
    if not os.path.lexists(target):
        return target
    base, ext = os.path.splitext(name)
    stamp = time.strftime("%H.%M.%S")
    i = 0
    while True:
        cand = os.path.join(dirpath, "%s %s%s%s" % (base, stamp, " %d" % i if i else "", ext))
        if not os.path.lexists(cand):
            return cand
        i += 1


def _same_device(a: str, b: str) -> bool:
    try:
        return os.lstat(a).st_dev == os.stat(b).st_dev
    except OSError:
        return False


def _mac_trash_dir() -> str:
    return os.path.expanduser("~/.Trash")


def _linux_trash_dir() -> str:
    base = os.environ.get("XDG_DATA_HOME") or os.path.expanduser("~/.local/share")
    return os.path.join(base, "Trash")


def _move_to_dir_trash(path: str, trash_dir: str) -> None:
    os.makedirs(trash_dir, exist_ok=True)
    if not _same_device(path, trash_dir):
        raise OSError("File ada di disk lain; buang lewat Finder.")
    target = _unique(trash_dir, os.path.basename(path))
    os.rename(path, target)


def _move_to_freedesktop_trash(path: str) -> None:
    trash = _linux_trash_dir()
    files_dir = os.path.join(trash, "files")
    info_dir = os.path.join(trash, "info")
    os.makedirs(files_dir, exist_ok=True)
    os.makedirs(info_dir, exist_ok=True)
    if not _same_device(path, files_dir):
        raise OSError("File ada di disk lain dari folder Sampah.")
    target = _unique(files_dir, os.path.basename(path))
    name = os.path.basename(target)
    with open(os.path.join(info_dir, name + ".trashinfo"), "w") as f:
        f.write("[Trash Info]\nPath=%s\nDeletionDate=%s\n"
                % (quote(os.path.abspath(path)), time.strftime("%Y-%m-%dT%H:%M:%S")))
    os.rename(path, target)


def _use_finder() -> bool:
    """Di macOS pakai Finder/~/.Trash. Tes memakai MACCLEANER_TEST_TRASH agar
    file tiruan tidak masuk ke Sampah sungguhan."""
    return sys.platform == "darwin" and not os.environ.get("MACCLEANER_TEST_TRASH")


def move_to_trash(paths: List[str]) -> List[Tuple[str, bool, str]]:
    """Buang ke Sampah. Hasil: [(path, berhasil, pesan)]."""
    results: List[Tuple[str, bool, str]] = []
    if not paths:
        return results
    if _use_finder():
        # Finder mendukung "Kembalikan" (Put Back) dan disk eksternal.
        remaining = [p for p in paths if os.path.lexists(p)]
        if remaining:
            try:
                subprocess.run(["osascript", "-e", _FINDER_DELETE] + remaining,
                               capture_output=True, timeout=300, check=True)
            except (OSError, subprocess.SubprocessError):
                pass
        for p in paths:
            if not os.path.lexists(p):
                results.append((p, True, "Dipindahkan ke Sampah"))
                continue
            try:
                _move_to_dir_trash(p, _mac_trash_dir())
                results.append((p, True, "Dipindahkan ke Sampah"))
            except OSError as e:
                results.append((p, False, _friendly(e)))
        return results

    for p in paths:
        try:
            _move_to_freedesktop_trash(p)
            results.append((p, True, "Dipindahkan ke Sampah"))
        except OSError as e:
            results.append((p, False, _friendly(e)))
    return results


def _friendly(e: OSError) -> str:
    if isinstance(e, PermissionError):
        return "Izin ditolak (file milik sistem/admin atau sedang dipakai)."
    if isinstance(e, FileNotFoundError):
        return "File sudah tidak ada."
    return str(e) or type(e).__name__


def trash_size() -> int:
    from .scanner import file_size
    dirs = [_mac_trash_dir()] if _use_finder() else [os.path.join(_linux_trash_dir(), "files")]
    total = 0
    for d in dirs:
        for root, subdirs, files in os.walk(d):
            for name in files:
                try:
                    total += file_size(os.lstat(os.path.join(root, name)))
                except OSError:
                    pass
    return total


def empty_trash() -> Tuple[bool, str]:
    """Kosongkan Sampah — PERMANEN."""
    if _use_finder():
        try:
            subprocess.run(["osascript", "-e", 'tell application "Finder" to empty trash'],
                           capture_output=True, timeout=600, check=True)
            return True, "Sampah dikosongkan."
        except (OSError, subprocess.SubprocessError) as e:
            return False, "Gagal mengosongkan Sampah lewat Finder: %s" % e
    trash = _linux_trash_dir()
    errors = 0
    for sub in ("files", "info"):
        d = os.path.join(trash, sub)
        if not os.path.isdir(d):
            continue
        for name in os.listdir(d):
            p = os.path.join(d, name)
            try:
                if os.path.isdir(p) and not os.path.islink(p):
                    shutil.rmtree(p)
                else:
                    os.unlink(p)
            except OSError:
                errors += 1
    if errors:
        return False, "%d item tidak bisa dihapus." % errors
    return True, "Sampah dikosongkan."


def reveal(path: str) -> bool:
    """Tampilkan di Finder / pengelola file."""
    try:
        if sys.platform == "darwin":
            subprocess.Popen(["open", "-R", path])
        else:
            target = path if os.path.isdir(path) else os.path.dirname(path)
            subprocess.Popen(["xdg-open", target], stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)
        return True
    except OSError:
        return False
