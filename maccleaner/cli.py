"""Perintah baris: `python3 -m maccleaner [app|disks|scan]`."""
from __future__ import annotations

import argparse
import os
import sys
import time

from . import __version__, history
from .disks import list_disks
from .rules import RuleMatcher
from .scanner import Scan
from .server import AppState, human, serve

COLORS = {"aman": "32", "hati": "33", "periksa": "36", "jangan": "31", "unknown": "90",
          "kritis": "31", "tinggi": "33", "sedang": "33", "info": "37"}


def c(text: str, level: str) -> str:
    if not sys.stdout.isatty() or os.environ.get("NO_COLOR"):
        return text
    return "\033[%sm%s\033[0m" % (COLORS.get(level, "0"), text)


def bar(pct: float, width: int = 30) -> str:
    full = int(round(pct / 100 * width))
    return "█" * full + "░" * (width - full)


def cmd_disks(_args) -> int:
    for d in list_disks():
        print("%-20s %s %5.1f%%  terpakai %s / %s, sisa %s" % (
            d["name"][:20], c(bar(d["percent"]), d["level"]), d["percent"],
            human(d["used"]), human(d["total"]), human(d["free"])))
        print("  " + c(d["message"], d["level"]))
    return 0


def cmd_scan(args) -> int:
    state = AppState()
    path = os.path.abspath(os.path.expanduser(args.path or state.home))
    scan = Scan(path, state.matcher)
    state.scan = scan
    history.prepare(scan, list_disks(state.home))
    scan.start()
    try:
        while scan.state == "running":
            if sys.stderr.isatty():
                pct = scan.fraction() * 100
                line = "\rMemindai %s %3d%%  %s · %s · %s   " % (
                    bar(pct, 24), pct, human(scan.bytes),
                    history.fmt_duration(time.time() - scan.started),
                    history.fmt_eta(scan.eta()))
                sys.stderr.write(line)
                sys.stderr.flush()
            time.sleep(0.2)
    except KeyboardInterrupt:
        scan.cancel()
        scan.wait()
    if sys.stderr.isatty():
        sys.stderr.write("\r" + " " * 100 + "\r")
    if scan.state == "error":
        print("Gagal: " + scan.error)
        return 1

    summ = state.summary()
    print(c("== Ringkasan: %s (%s, %d file, %s) ==" % (
        summ["display"], human(summ["scanned"]), summ["files"],
        history.fmt_duration(summ["elapsed"])), "info"))
    for ins in summ["insights"]:
        print(" • " + c(ins["text"], ins["level"]))

    print()
    print(c("== Kenapa penuh? (per kategori) ==", "info"))
    total = summ["scanned"] or 1
    for cat in summ["categories"][:12]:
        pct = cat["size"] / total * 100
        print("  %-28s %10s  %s %4.1f%%" % (cat["label"], human(cat["size"]), bar(pct, 20), pct))

    print()
    print(c("== Folder terbesar ==", "info"))
    node = state.node(None)
    for it in node["items"][: args.top]:
        r = it["rule"]
        print("  %10s  %-50s %s" % (human(it["size"]), (it["display"] or it["name"])[-50:],
                                   c("[%s]" % r["safetyLabel"], r["safety"])))

    print()
    print(c("== Rekomendasi pembersihan ==", "info"))
    recs = state.recommendations()
    if recs["trash"]:
        print("  %10s  Sampah — kosongkan Sampah untuk benar-benar membebaskan ruang" % human(recs["trash"]))
    for g in recs["groups"][: args.top]:
        r = g["rule"]
        print("  %10s  %-40s %s (%d lokasi)" % (human(g["total"]), r["title"][:40],
                                               c("[%s]" % r["safetyLabel"], r["safety"]), len(g["items"])))
        print("             %s" % r["why"])
        if r["command"]:
            print("             Perintah: %s" % r["command"])
        elif g["kind"] == "manual" and r["how"]:
            print("             Cara: %s" % r["how"])

    print()
    print(c("== File terbesar ==", "info"))
    for it in state.largefiles(args.top)["items"]:
        r = it["rule"]
        print("  %10s  %-50s %s" % (human(it["size"]), it["display"][-50:],
                                   c("[%s]" % r["safetyLabel"], r["safety"])))
    print()
    print("Untuk membersihkan dengan aman, jalankan aplikasinya: python3 -m maccleaner")
    return 0


def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="maccleaner",
                                description="Cari tahu kenapa disk penuh dan apa yang aman dihapus.")
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="cmd")
    a = sub.add_parser("app", help="buka aplikasi di browser (bawaan)")
    a.add_argument("--port", type=int, default=8765)
    a.add_argument("--no-browser", action="store_true")
    a.add_argument("--auto-exit", action="store_true",
                   help="berhenti sendiri setelah tab browser ditutup")
    sub.add_parser("disks", help="tampilkan pemakaian disk")
    s = sub.add_parser("scan", help="pindai folder dan tampilkan laporan di terminal")
    s.add_argument("path", nargs="?")
    s.add_argument("--top", type=int, default=15)
    args = p.parse_args(argv)

    if args.cmd == "disks":
        return cmd_disks(args)
    if args.cmd == "scan":
        return cmd_scan(args)
    serve(port=getattr(args, "port", 8765),
          open_browser=not getattr(args, "no_browser", False),
          auto_exit=getattr(args, "auto_exit", False))
    return 0
