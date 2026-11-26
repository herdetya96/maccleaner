#!/usr/bin/env python3
"""Membuat macos/Sources/MacCleanerCore/RuleData.swift dari maccleaner/rules.py.

Dengan begitu versi Python dan versi SwiftUI selalu memakai basis pengetahuan
yang sama. Jalankan ulang setiap kali rules.py diubah:

    python3 scripts/gen_swift_rules.py          # tulis file
    python3 scripts/gen_swift_rules.py --check  # gagal bila file belum diperbarui
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)

from maccleaner import rules as R  # noqa: E402
from maccleaner.scanner import OLD_DOWNLOADS_RULE  # noqa: E402

OUT = os.path.join(ROOT, "macos", "Sources", "MacCleanerCore", "RuleData.swift")


MODES = {"self": "folder", "contents": "contents"}  # `self` adalah kata kunci Swift


def s(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'


def b(v: bool) -> str:
    return "true" if v else "false"


def rule_literal(r, indent="        ") -> str:
    pats = ", ".join(s(p) for p in r.patterns)
    return (
        f"{indent}Rule(id: {s(r.id)}, patterns: [{pats}],\n"
        f"{indent}     title: {s(r.title)}, category: {s(r.category)}, safety: .{r.safety},\n"
        f"{indent}     why: {s(r.why)},\n"
        f"{indent}     effect: {s(r.effect)},\n"
        f"{indent}     how: {s(r.how)},\n"
        f"{indent}     command: {s(r.command)},\n"
        f"{indent}     inherit: {b(r.inherit)}, lock: {b(r.lock)}, mode: .{MODES[r.mode]}, "
        f"deletable: {b(r.deletable)}, granular: {b(r.granular)})"
    )


def render() -> str:
    lines = [
        "// FILE INI DIBUAT OTOMATIS oleh scripts/gen_swift_rules.py dari maccleaner/rules.py.",
        "// Jangan diedit manual — ubah rules.py lalu jalankan ulang skripnya.",
        "",
        "public extension Rule {",
        "    /// Semua aturan, dari yang paling spesifik ke yang paling umum.",
        "    static let all: [Rule] = [",
    ]
    lines.append(",\n".join(rule_literal(r) for r in R.RULES))
    lines += [
        "    ]",
        "",
        "    /// Aturan untuk file besar lama di folder Unduhan.",
        "    static let oldDownloads: Rule =",
        rule_literal(OLD_DOWNLOADS_RULE, "        ").lstrip(),
        "}",
        "",
        "public enum RuleTables {",
        "    public static let categories: [(id: String, label: String)] = [",
    ]
    lines += [f"        ({s(k)}, {s(v)})," for k, v in R.CATEGORIES.items()]
    lines += [
        "    ]",
        "    public static let protectedPaths: Set<String> = [" +
        ", ".join(s(p) for p in sorted(R.PROTECTED_PATHS)) + "]",
        "    public static let protectedHomeChildren: Set<String> = [" +
        ", ".join(s(p) for p in sorted(R.PROTECTED_HOME_CHILDREN)) + "]",
        "}",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    text = render()
    if "--check" in sys.argv:
        try:
            with open(OUT, encoding="utf-8") as f:
                current = f.read()
        except FileNotFoundError:
            current = ""
        if current != text:
            print("RuleData.swift tidak sinkron dengan rules.py. Jalankan: python3 scripts/gen_swift_rules.py")
            return 1
        print("RuleData.swift sinkron.")
        return 0
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print("Ditulis: " + os.path.relpath(OUT, ROOT))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
