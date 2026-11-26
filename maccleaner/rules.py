"""Basis pengetahuan: apa isi sebuah folder/file, kenapa bisa besar, dan
apakah aman dihapus.

Setiap aturan (Rule) dicocokkan dengan path lengkap memakai pola glob
sederhana:

* ``~``   di awal  -> folder rumah pengguna
* ``*``             -> satu bagian path (tanpa ``/``)
* ``**/``           -> nol atau lebih folder
* ``/**`` di akhir  -> semua isi di bawahnya

Aturan diperiksa berurutan; aturan PERTAMA yang cocok yang dipakai, jadi
aturan yang lebih spesifik harus ditulis lebih dulu.
"""
from __future__ import annotations

import os
import re
import sys
from typing import Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Tingkat keamanan
# ---------------------------------------------------------------------------
AMAN = "aman"          # aman dihapus, akan dibuat ulang / tidak dibutuhkan
HATI = "hati"          # bisa dihapus, tapi ada konsekuensinya
PERIKSA = "periksa"    # file pribadi Anda - keputusan Anda sendiri
JANGAN = "jangan"      # jangan dihapus manual
UNKNOWN = "unknown"    # tidak dikenali

SAFETY_LABELS = {
    AMAN: "Aman dihapus",
    HATI: "Hati-hati",
    PERIKSA: "Periksa dulu",
    JANGAN: "Jangan dihapus",
    UNKNOWN: "Tidak dikenali",
}

CATEGORIES = {
    "cache": "Cache aplikasi",
    "log": "Log & laporan crash",
    "dev": "File developer",
    "trash": "Sampah (Trash)",
    "downloads": "Unduhan",
    "installer": "Installer & arsip",
    "backup": "Backup iPhone/iPad",
    "vm": "Docker & virtual machine",
    "apps": "Aplikasi",
    "appdata": "Data aplikasi",
    "media": "Foto, video & musik",
    "docs": "Dokumen & file pribadi",
    "mail": "Mail & Pesan",
    "cloud": "iCloud & cloud sync",
    "system": "Sistem",
    "other": "Lainnya",
}


class Rule:
    __slots__ = (
        "id", "patterns", "title", "category", "safety", "why", "effect",
        "how", "command", "inherit", "lock", "mode", "deletable", "granular",
    )

    def __init__(self, id: str, patterns, title: str, category: str,
                 safety: str, why: str, effect: str = "", how: str = "",
                 command: str = "", inherit: bool = True, lock: bool = False,
                 mode: str = "self", deletable: bool = True):
        self.id = id
        self.patterns = [patterns] if isinstance(patterns, str) else list(patterns)
        self.title = title
        self.category = category
        self.safety = safety
        self.why = why            # kenapa besar / isinya apa
        self.effect = effect      # apa yang terjadi kalau dihapus
        self.how = how            # cara membersihkan yang benar
        self.command = command    # perintah Terminal (opsional)
        self.inherit = inherit    # isi di bawahnya ikut aturan ini
        self.lock = lock          # isi di bawahnya TIDAK boleh menimpa aturan ini
        self.mode = mode          # "self" = buang foldernya, "contents" = buang isinya
        self.deletable = deletable and safety != JANGAN
        # granular=False: hanya folder itu sendiri (dan anak langsungnya) yang
        # boleh dibuang, bukan file di dalamnya. Membuang satu file di dalam
        # backup iPhone, .app, atau simulator akan merusak keseluruhannya.
        self.granular = False

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "title": self.title,
            "category": self.category,
            "categoryLabel": CATEGORIES.get(self.category, self.category),
            "safety": self.safety,
            "safetyLabel": SAFETY_LABELS[self.safety],
            "why": self.why,
            "effect": self.effect,
            "how": self.how,
            "command": self.command,
            "mode": self.mode,
            "deletable": self.deletable,
        }


R = Rule

# ---------------------------------------------------------------------------
# Daftar aturan (spesifik -> umum)
# ---------------------------------------------------------------------------
RULES: List[Rule] = [
    # ----- Sampah ---------------------------------------------------------
    R("trash", ["~/.Trash", "~/.local/share/Trash", "/Volumes/*/.Trashes"],
      "Sampah (Trash)", "trash", AMAN,
      "File yang sudah Anda hapus tetap memakan ruang disk sampai Sampah dikosongkan.",
      "File di dalamnya hilang permanen.",
      "Klik kanan ikon Sampah di Dock → Kosongkan Sampah, atau tombol "
      "\"Kosongkan Sampah\" di aplikasi ini.",
      deletable=False, lock=True),

    # ----- iCloud & cloud sync (berbahaya: hapus = hapus di semua perangkat)
    R("icloud", "~/Library/Mobile Documents", "iCloud Drive", "cloud", JANGAN,
      "Salinan lokal file iCloud Drive. Bisa besar kalau \"Optimalkan Penyimpanan Mac\" mati.",
      "Menghapus di sini juga MENGHAPUS file dari iCloud dan semua perangkat Anda.",
      "Untuk mengosongkan ruang tanpa menghapus: di Finder klik kanan file/folder iCloud → "
      "\"Hapus Unduhan\". Atau aktifkan Pengaturan Sistem → Apple ID → iCloud → "
      "\"Optimalkan Penyimpanan Mac\".", lock=True),
    R("cloudstorage", ["~/Library/CloudStorage", "~/Dropbox", "~/OneDrive*", "~/Google Drive"],
      "Folder sinkronisasi cloud (Dropbox / Google Drive / OneDrive)", "cloud", JANGAN,
      "File yang disinkronkan dari layanan cloud dan disimpan juga secara lokal.",
      "Menghapus di sini ikut menghapus file di cloud.",
      "Ubah file menjadi \"online-only\" lewat klik kanan di Finder "
      "(mis. \"Free up space\" / \"Hapus Unduhan\") agar ruang lokal kosong tanpa menghapus file.",
      lock=True),

    # ----- Xcode / Apple developer ---------------------------------------
    R("xcode-deriveddata", ["~/Library/Developer/Xcode/DerivedData", "**/DerivedData"],
      "Xcode DerivedData", "dev", AMAN,
      "Hasil build, index, dan file sementara Xcode. Tumbuh terus setiap proyek di-build.",
      "Build berikutnya lebih lama karena Xcode membuat ulang semuanya.",
      "Tutup Xcode dulu, lalu hapus isinya.", mode="contents"),
    R("xcode-archives", "~/Library/Developer/Xcode/Archives",
      "Xcode Archives", "dev", HATI,
      "Arsip build aplikasi (.xcarchive) termasuk file dSYM untuk membaca laporan crash.",
      "Anda tidak bisa lagi men-symbolicate crash atau upload ulang versi lama tersebut.",
      "Hapus arsip lama lewat Xcode → Window → Organizer → Archives. Simpan versi yang masih beredar di App Store."),
    R("xcode-devicesupport", "~/Library/Developer/Xcode/*DeviceSupport",
      "Xcode Device Support", "dev", AMAN,
      "Simbol debug untuk setiap versi iOS/watchOS dari perangkat yang pernah dicolok (2–5 GB per versi).",
      "Dibuat ulang otomatis saat perangkat dicolok lagi.",
      "Hapus folder versi iOS lama yang sudah tidak Anda pakai.", mode="contents"),
    R("xcode-devicelogs", ["~/Library/Developer/Xcode/iOS Device Logs",
                           "~/Library/Developer/Xcode/UserData/Previews",
                           "~/Library/Developer/Xcode/UserData/IB Support"],
      "Log & preview Xcode", "dev", AMAN,
      "Log perangkat dan cache SwiftUI Preview.", "Dibuat ulang bila perlu.", mode="contents"),
    R("simulator-caches", "~/Library/Developer/CoreSimulator/Caches",
      "Cache Simulator iOS", "dev", AMAN,
      "Cache dyld dan data sementara simulator.", "Dibuat ulang otomatis.", mode="contents"),
    R("simulator-devices", "~/Library/Developer/CoreSimulator/Devices",
      "Simulator iOS", "dev", HATI,
      "Setiap simulator menyimpan aplikasi & datanya sendiri. Simulator dari versi Xcode lama sering tertinggal.",
      "Aplikasi & data uji di simulator hilang.",
      "Hapus simulator yang tidak tersedia/terpakai lewat Terminal.",
      command="xcrun simctl delete unavailable"),
    R("simulator-runtimes", ["/Library/Developer/CoreSimulator/Volumes",
                             "/Library/Developer/CoreSimulator/Images",
                             "/Library/Developer/CoreSimulator/Profiles/Runtimes"],
      "Runtime Simulator iOS", "dev", HATI,
      "Image sistem iOS/watchOS/tvOS untuk simulator (5–10 GB per versi).",
      "Versi simulator itu tidak bisa dipakai sampai diunduh ulang.",
      "Hapus lewat Xcode → Settings → Platforms, atau Terminal.",
      command="xcrun simctl runtime list   # lalu: xcrun simctl runtime delete <ID>",
      deletable=False),
    R("xcode-app", "/Applications/Xcode*.app", "Xcode", "apps", HATI,
      "Xcode sendiri berukuran 10–40 GB.",
      "Anda tidak bisa membuat aplikasi iOS/macOS sampai menginstal ulang.",
      "Hapus versi beta/lama bila punya lebih dari satu Xcode."),
    R("dev-container", "~/Library/Developer", "Folder Developer", "dev", PERIKSA,
      "Berisi data Xcode, simulator, dan alat developer lain.", inherit=False),

    # ----- Backup iPhone --------------------------------------------------
    R("ios-backup", "~/Library/Application Support/MobileSync/Backup",
      "Backup iPhone/iPad", "backup", HATI,
      "Backup lokal iPhone/iPad dari Finder. Satu backup bisa 10–200 GB.",
      "Backup tersebut hilang. Pastikan Anda punya backup di iCloud atau tidak membutuhkannya lagi.",
      "Finder → pilih iPhone → \"Kelola Cadangan…\" → hapus backup lama."),
    R("ios-updates", ["~/Library/iTunes/*Software Updates", "**/*.ipsw"],
      "File update iOS (.ipsw)", "installer", AMAN,
      "File firmware iOS yang diunduh saat update lewat Mac.",
      "Diunduh ulang bila diperlukan."),

    # ----- Docker & VM ----------------------------------------------------
    R("docker", ["~/Library/Containers/com.docker.docker",
                 "~/Library/Group Containers/group.com.docker"],
      "Docker Desktop", "vm", HATI,
      "Disk virtual Docker (Docker.raw) berisi semua image, container, volume, dan build cache. "
      "File ini membesar dan tidak mengecil sendiri.",
      "Menghapus manual = semua image, container, dan volume Docker hilang.",
      "Bersihkan dari dalam Docker, bukan dengan menghapus file.",
      command="docker system prune -a --volumes", deletable=False),
    R("orbstack", ["~/.orbstack", "~/Library/Group Containers/*.dev.orbstack"],
      "OrbStack", "vm", HATI,
      "Data container/VM OrbStack.", "Container & image hilang.",
      command="docker system prune -a", deletable=False),
    R("colima", "~/.colima", "Colima", "vm", HATI,
      "Disk VM Colima untuk Docker.", "Container & image hilang.",
      command="docker system prune -a"),
    R("docker-linux", "/var/lib/docker", "Docker", "vm", HATI,
      "Image, container, dan volume Docker.", "Data Docker hilang.",
      command="docker system prune -a", deletable=False),
    R("vm-files", ["~/Parallels", "**/*.pvm", "**/*.vmwarevm", "**/*.utm",
                   "~/Virtual Machines.localized", "~/VirtualBox VMs",
                   "~/Library/Containers/com.utmapp.UTM"],
      "Virtual machine", "vm", HATI,
      "Disk virtual (Windows/Linux) biasanya 20–100 GB.",
      "Seluruh isi VM (OS, aplikasi, file di dalamnya) hilang.",
      "Hapus VM yang tidak dipakai dari aplikasi Parallels/VMware/UTM/VirtualBox."),
    R("vm-disks", ["**/*.vmdk", "**/*.vdi", "**/*.qcow2", "**/*.vhd", "**/*.vhdx"],
      "Disk virtual machine", "vm", HATI,
      "File disk virtual.", "Isi VM hilang."),

    # ----- Android / Java / JS / dll -------------------------------------
    R("android-avd", "~/.android/avd", "Emulator Android", "dev", HATI,
      "Image emulator Android (masing-masing 2–10 GB).", "Emulator dan datanya hilang.",
      "Hapus dari Android Studio → Device Manager."),
    R("android-sdk-images", "~/Library/Android/sdk/system-images", "System image Android SDK", "dev", HATI,
      "Image sistem untuk emulator Android.", "Perlu diunduh ulang lewat SDK Manager.",
      "Android Studio → Settings → Android SDK → hapus centang versi lama."),
    R("gradle", ["~/.gradle/caches", "~/.gradle/wrapper/dists"],
      "Cache Gradle", "dev", AMAN,
      "Dependensi & distribusi Gradle yang diunduh.", "Diunduh ulang saat build berikutnya (lebih lama).",
      mode="contents"),
    R("maven", "~/.m2/repository", "Cache Maven", "dev", AMAN,
      "Library Java yang diunduh Maven.", "Diunduh ulang saat build.", mode="contents"),
    R("npm-cache", ["~/.npm", "~/.yarn/berry/cache", "~/.pnpm-store", "~/Library/pnpm/store",
                    "~/.bun/install/cache"],
      "Cache npm / yarn / pnpm / bun", "dev", AMAN,
      "Paket JavaScript yang pernah diunduh.", "Diunduh ulang saat install berikutnya.",
      command="npm cache clean --force", mode="contents"),
    R("node-modules", "**/node_modules", "node_modules", "dev", AMAN,
      "Dependensi proyek JavaScript. Tiap proyek bisa ratusan MB, dan proyek lama sering terlupakan.",
      "Jalankan `npm install` lagi di proyek itu bila ingin mengerjakannya.",
      "Aman dihapus terutama untuk proyek yang sudah lama tidak disentuh."),
    R("next-build", ["**/.next/cache", "**/.nuxt", "**/.parcel-cache", "**/.turbo",
                     "**/.angular/cache", "**/.svelte-kit"],
      "Cache build web", "dev", AMAN,
      "Cache build framework web.", "Dibuat ulang saat build berikutnya."),
    R("cocoapods", ["~/.cocoapods/repos", "~/Library/Caches/CocoaPods"],
      "Cache CocoaPods", "dev", AMAN, "Spec repo & cache CocoaPods.", "Diunduh ulang.",
      command="pod cache clean --all", mode="contents"),
    R("pods", "**/Pods", "Pods (CocoaPods)", "dev", AMAN,
      "Dependensi proyek iOS.", "Jalankan `pod install` lagi."),
    R("cargo", ["~/.cargo/registry", "~/.cargo/git"], "Cache Cargo (Rust)", "dev", AMAN,
      "Crate Rust yang diunduh.", "Diunduh ulang saat build.", mode="contents"),
    R("rustup", "~/.rustup/toolchains", "Toolchain Rust", "dev", HATI,
      "Versi compiler Rust yang terinstal.", "Versi yang dihapus perlu diinstal ulang.",
      command="rustup toolchain list"),
    R("go-mod", "~/go/pkg/mod", "Cache modul Go", "dev", AMAN,
      "Modul Go yang diunduh.", "Diunduh ulang.", command="go clean -modcache", deletable=False),
    R("pub-cache", "~/.pub-cache", "Cache Dart/Flutter", "dev", AMAN,
      "Paket Dart/Flutter.", "Diunduh ulang.", command="flutter pub cache clean"),
    R("conda-pkgs", ["~/miniconda3/pkgs", "~/anaconda3/pkgs", "~/miniforge3/pkgs",
                     "~/opt/anaconda3/pkgs", "~/.conda/pkgs"],
      "Cache paket Conda", "dev", AMAN,
      "Arsip paket conda yang sudah terpasang.", "Tidak memengaruhi environment yang ada.",
      command="conda clean --all"),
    R("pyenv-nvm", ["~/.nvm/versions", "~/.pyenv/versions", "~/.rbenv/versions",
                    "~/.volta/tools"],
      "Versi Node/Python/Ruby terpasang", "dev", HATI,
      "Banyak versi runtime terpasang berdampingan.",
      "Proyek yang memakai versi itu tidak bisa jalan sampai diinstal ulang.",
      "Hapus versi lama lewat `nvm uninstall`, `pyenv uninstall`, dsb."),
    R("venv", ["**/.venv", "**/venv"], "Python virtualenv", "dev", AMAN,
      "Paket Python milik satu proyek.", "Buat ulang dengan `python -m venv` + `pip install -r requirements.txt`."),
    R("pycache", ["**/__pycache__", "**/.pytest_cache", "**/.mypy_cache", "**/.ruff_cache"],
      "Cache Python", "dev", AMAN, "Bytecode & cache alat Python.", "Dibuat ulang otomatis."),
    R("terraform", ["**/.terraform", "**/.dart_tool"], "Cache alat build", "dev", AMAN,
      "Plugin/cache yang diunduh alat build.", "Diunduh ulang."),
    R("huggingface", ["~/.cache/huggingface", "~/.cache/torch", "~/.cache/lm-studio",
                      "~/.lmstudio/models", "~/.ollama/models"],
      "Model AI (Hugging Face / Ollama / LM Studio)", "dev", HATI,
      "Model AI yang diunduh; satu model bisa 4–70 GB.",
      "Harus diunduh ulang (lama & besar) bila dibutuhkan lagi.",
      "Hapus model yang tidak dipakai (mis. `ollama rm <nama>`)."),
    R("vscode-cache", ["~/Library/Application Support/Code/CachedData",
                       "~/Library/Application Support/Code/CachedExtensionVSIXs",
                       "~/Library/Application Support/Code/User/workspaceStorage",
                       "~/Library/Application Support/Cursor/CachedData"],
      "Cache VS Code", "cache", AMAN,
      "Cache versi lama & data workspace VS Code.", "Dibuat ulang; riwayat UI per-workspace bisa hilang.",
      mode="contents"),
    R("git", "**/.git", "Repositori Git", "dev", JANGAN,
      "Seluruh riwayat versi proyek.", "Riwayat commit proyek hilang.",
      "Untuk memperkecil: `git gc --aggressive` di folder proyek.", lock=True),

    # ----- Homebrew -------------------------------------------------------
    R("brew-cache", "~/Library/Caches/Homebrew", "Cache Homebrew", "cache", AMAN,
      "Installer paket Homebrew yang sudah diunduh.", "Tidak memengaruhi paket terpasang.",
      command="brew cleanup -s", mode="contents"),
    R("brew", ["/opt/homebrew", "/usr/local/Cellar", "/usr/local/Caskroom"],
      "Paket Homebrew", "dev", HATI,
      "Program yang terpasang lewat Homebrew.", "Program terkait berhenti berfungsi.",
      "Copot dengan `brew uninstall <nama>`; versi lama: `brew cleanup`.",
      command="brew cleanup", deletable=False, lock=True),

    # ----- Cache di Application Support (Electron, browser, dll) ----------
    R("chrome-sw", ["~/Library/Application Support/Google/Chrome/*/Service Worker/CacheStorage",
                    "~/Library/Application Support/Microsoft Edge/*/Service Worker/CacheStorage",
                    "~/Library/Application Support/BraveSoftware/Brave-Browser/*/Service Worker/CacheStorage"],
      "Cache situs web (browser)", "cache", AMAN,
      "Situs web menyimpan cache offline di sini; bisa beberapa GB.",
      "Situs akan memuat ulang data; Anda tetap login.", mode="contents"),
    R("app-caches", ["~/Library/Application Support/*/Cache",
                     "~/Library/Application Support/*/Code Cache",
                     "~/Library/Application Support/*/GPUCache",
                     "~/Library/Application Support/*/DawnCache",
                     "~/Library/Application Support/*/Service Worker/CacheStorage",
                     "~/Library/Application Support/*/*/Cache",
                     "~/Library/Application Support/Spotify/PersistentCache",
                     "~/Library/Application Support/Adobe/Common/Media Cache Files",
                     "~/Library/Application Support/Adobe/Common/Media Cache"],
      "Cache aplikasi (Slack, Discord, Spotify, Adobe, dll)", "cache", AMAN,
      "Aplikasi berbasis Electron/Chromium dan editor media menyimpan cache besar di sini.",
      "Dibuat ulang otomatis; aplikasi mungkin sedikit lambat saat pertama dibuka. "
      "Sebaiknya tutup aplikasinya dulu.", mode="contents"),
    R("container-caches", ["~/Library/Containers/*/Data/Library/Caches",
                           "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads"],
      "Cache aplikasi (sandbox)", "cache", AMAN,
      "Cache aplikasi dari App Store yang berjalan di sandbox.",
      "Dibuat ulang otomatis.", mode="contents"),

    # ----- Pesan & Mail ---------------------------------------------------
    R("messages-attachments", "~/Library/Messages/Attachments",
      "Lampiran iMessage", "mail", HATI,
      "Foto, video, dan file yang dikirim/diterima lewat Pesan (iMessage).",
      "Lampiran hilang dari percakapan (muncul sebagai file hilang).",
      "Lebih aman lewat Pesan → Settings → \"Simpan pesan: 1 Tahun/30 Hari\", atau "
      "Pengaturan Sistem → Umum → Penyimpanan → Pesan → Tinjau Lampiran Besar.",
      deletable=False),
    R("messages", "~/Library/Messages", "Pesan (iMessage)", "mail", JANGAN,
      "Database percakapan iMessage.", "Riwayat chat rusak/hilang.", inherit=False),
    R("mail", "~/Library/Mail", "Apple Mail", "mail", JANGAN,
      "Salinan lokal email & lampiran di aplikasi Mail.",
      "Database Mail rusak; email lokal (On My Mac) hilang.",
      "Hapus email besar dari aplikasi Mail, atau hapus akun lalu tambahkan lagi untuk mengunduh ulang.",
      lock=True),
    R("whatsapp", "~/Library/Group Containers/*WhatsApp*", "WhatsApp", "mail", PERIKSA,
      "Foto, video, dan dokumen dari chat WhatsApp.",
      "Media chat hilang dari Mac.",
      "WhatsApp → Settings → Storage untuk menghapus media per chat.", deletable=False),
    R("telegram", "~/Library/Group Containers/*Telegram*", "Telegram", "mail", PERIKSA,
      "Cache media Telegram (bisa puluhan GB).", "Media diunduh ulang dari server Telegram.",
      "Telegram → Settings → Data and Storage → Storage Usage → Clear Cache.", deletable=False),

    # ----- Media library --------------------------------------------------
    R("photos", "**/*.photoslibrary", "Perpustakaan Foto", "media", JANGAN,
      "Semua foto & video di aplikasi Foto.",
      "Menghapus/mengubah isi paket ini bisa MERUSAK seluruh perpustakaan foto.",
      "Hapus foto dari aplikasi Foto lalu kosongkan \"Baru Dihapus\". Untuk hemat ruang: "
      "Foto → Settings → iCloud → \"Optimalkan Penyimpanan Mac\".", lock=True),
    R("fcp", ["**/*.fcpbundle", "**/*.imovielibrary"], "Library Final Cut / iMovie", "media", PERIKSA,
      "Proyek video beserta file render & proxy.",
      "Proyek video hilang.",
      "Hapus file render dari aplikasinya: File → Delete Generated Library Files.",
      lock=True),
    R("garageband", ["/Library/Application Support/GarageBand",
                     "/Library/Application Support/Logic",
                     "/Library/Audio/Apple Loops"],
      "Sound library GarageBand/Logic", "media", HATI,
      "Instrumen & loop audio (bisa 10–70 GB).",
      "Instrumen/loop tidak tersedia sampai diunduh ulang.",
      "Kelola dari GarageBand/Logic → Sound Library.", deletable=False),
    R("music-lib", ["~/Music/Music", "~/Music/iTunes"], "Perpustakaan Musik", "media", PERIKSA,
      "Lagu, podcast, dan video yang tersimpan lokal.",
      "File musik lokal hilang.", "Hapus dari aplikasi Musik.", lock=True),
    R("steam", "~/Library/Application Support/Steam/steamapps", "Game Steam", "apps", PERIKSA,
      "Game yang terpasang lewat Steam.", "Game harus diunduh ulang.",
      "Copot game dari Steam → Library → Manage → Uninstall.", deletable=False),

    # ----- Log ------------------------------------------------------------
    R("user-logs", ["~/Library/Logs", "/Library/Logs/DiagnosticReports"],
      "Log & laporan crash", "log", AMAN,
      "Catatan aktivitas aplikasi dan laporan crash.",
      "Tidak ada; hanya berguna untuk diagnosis masalah.", mode="contents"),
    R("cores", "/cores", "Core dump", "log", AMAN,
      "Dump memori saat program crash; satu file bisa beberapa GB.", "Tidak ada.",
      mode="contents"),
    R("system-logs", ["/Library/Logs", "/private/var/log", "/var/log"],
      "Log sistem", "log", HATI,
      "Log layanan sistem.", "Tidak berbahaya, tapi butuh izin admin.",
      "macOS merotasi log ini sendiri.", deletable=False),
    R("apt-cache", "/var/cache/apt", "Cache APT", "cache", AMAN,
      "Paket .deb yang sudah diunduh.", "Tidak ada.", command="sudo apt clean", deletable=False),

    # ----- Cache umum -----------------------------------------------------
    R("user-caches-item", "~/Library/Caches/*", "Cache aplikasi", "cache", AMAN,
      "Data sementara aplikasi untuk mempercepat kerja.",
      "Dibuat ulang otomatis. Sebaiknya tutup aplikasinya dulu."),
    R("user-caches", ["~/Library/Caches", "~/.cache"], "Cache aplikasi", "cache", AMAN,
      "Semua aplikasi menyimpan data sementara di sini; bisa tumbuh sampai puluhan GB.",
      "Dibuat ulang otomatis. Beberapa aplikasi bisa sedikit lambat saat pertama dibuka.",
      "Tutup aplikasi yang sedang terbuka, lalu hapus isinya.", mode="contents"),
    R("system-caches", "/Library/Caches", "Cache sistem", "cache", HATI,
      "Cache bersama untuk semua pengguna.", "Butuh izin admin; dibuat ulang otomatis.",
      "Biasanya cukup restart Mac.", deletable=False),

    # ----- Aplikasi ---------------------------------------------------------
    R("app-bundle", ["/Applications/*.app", "/Applications/*/*.app", "~/Applications/*.app"],
      "Aplikasi", "apps", HATI,
      "Aplikasi terpasang. Game & suite kreatif bisa puluhan GB.",
      "Aplikasi tidak bisa dipakai. Data & pengaturannya di ~/Library tetap tersisa.",
      "Seret ke Sampah dari folder Aplikasi. Untuk aplikasi dengan uninstaller (Adobe, Office), pakai uninstaller-nya."),
    R("applications", ["/Applications", "~/Applications"], "Folder Aplikasi", "apps", PERIKSA,
      "Semua aplikasi terpasang.", inherit=False),

    # ----- Data aplikasi --------------------------------------------------
    R("app-support-item", ["~/Library/Application Support/*", "~/Library/Containers/*",
                           "~/Library/Group Containers/*"],
      "Data aplikasi", "appdata", PERIKSA,
      "Data, database, dan pengaturan milik satu aplikasi.",
      "Data aplikasi tersebut hilang (dokumen internal, login, pengaturan). "
      "Aman hanya bila aplikasinya sudah dicopot.",
      "Bila aplikasinya sudah tidak ada di Mac, folder ini adalah sisa yang aman dibuang."),
    R("app-support", ["~/Library/Application Support", "~/Library/Containers",
                      "~/Library/Group Containers"],
      "Data aplikasi", "appdata", PERIKSA,
      "Data milik semua aplikasi.", inherit=False),
    R("user-library", "~/Library", "Library pengguna", "appdata", PERIKSA,
      "Pengaturan, cache, dan data semua aplikasi Anda.",
      "Jangan hapus folder ini secara utuh.", inherit=False, deletable=False),

    # ----- Installer & arsip (file) --------------------------------------
    R("installer", ["**/*.dmg", "**/*.pkg", "**/*.mpkg", "**/*.xip"],
      "Installer", "installer", AMAN,
      "File installer aplikasi. Setelah aplikasi terpasang, file ini tidak dibutuhkan lagi.",
      "Tidak ada, kecuali Anda ingin menginstal ulang tanpa mengunduh."),
    R("archive", ["**/*.zip", "**/*.rar", "**/*.7z", "**/*.tar", "**/*.tar.gz", "**/*.tgz",
                  "**/*.iso"],
      "File arsip", "installer", PERIKSA,
      "Arsip terkompresi. Sering sudah diekstrak sehingga isinya tersimpan dua kali.",
      "Isi arsip hilang bila belum diekstrak."),
    R("video-file", ["**/*.mov", "**/*.mp4", "**/*.mkv", "**/*.avi", "**/*.m4v", "**/*.braw",
                     "**/*.r3d"],
      "File video", "media", PERIKSA,
      "Video, terutama rekaman layar dan 4K, cepat memenuhi disk.",
      "Video hilang. Pindahkan ke disk eksternal bila masih perlu."),

    # ----- Folder pribadi -------------------------------------------------
    R("downloads", "~/Downloads", "Unduhan", "downloads", PERIKSA,
      "Semua yang Anda unduh. Sering berisi installer, ZIP, dan file sekali pakai.",
      "File yang dihapus hilang (bisa dari Sampah dulu).",
      "Urutkan berdasarkan ukuran/tanggal dan buang yang sudah tidak diperlukan."),
    R("desktop-docs", ["~/Desktop", "~/Documents"], "Dokumen & Desktop", "docs", PERIKSA,
      "File pribadi Anda.", "File pribadi hilang.",
      "Periksa satu per satu. Arsipkan ke disk eksternal bila perlu."),
    R("media-folders", ["~/Movies", "~/Pictures", "~/Music"], "Media pribadi", "media", PERIKSA,
      "Foto, video, dan musik Anda.", "File hilang.",
      "Pindahkan ke disk eksternal atau cloud bila jarang dibuka."),

    # ----- Sistem ---------------------------------------------------------
    R("vm-swap", ["/private/var/vm", "/System/Volumes/VM"], "Memori virtual (swap & sleepimage)",
      "system", JANGAN,
      "macOS memakai disk sebagai tambahan RAM (swap) dan untuk menyimpan isi RAM saat tidur.",
      "Sistem bisa crash. Ruang ini kosong sendiri setelah restart.",
      "Restart Mac dan tutup aplikasi berat untuk memperkecil swap.", lock=True),
    R("var-folders", "/private/var/folders", "File sementara sistem", "system", JANGAN,
      "Cache & file sementara per-pengguna milik macOS. Bisa membengkak berbulan-bulan tanpa restart.",
      "Aplikasi yang sedang berjalan bisa error.",
      "Restart Mac; macOS membersihkannya sendiri.", lock=True),
    R("system", ["/System", "/usr", "/bin", "/sbin", "/private/etc", "/private/var/db",
                 "/Library/Apple", "/proc", "/sys", "/dev", "/etc", "/boot", "/lib", "/lib64",
                 "/usr/lib", "/snap"],
      "File sistem", "system", JANGAN,
      "Bagian dari sistem operasi.", "Mac bisa gagal booting.",
      "Jangan diubah. Pembaruan macOS mengelolanya sendiri.", lock=True),
    R("private-var", ["/private/var", "/private", "/var"], "Data sistem", "system", JANGAN,
      "Data internal sistem operasi.", "Sistem bisa rusak.", lock=False),
    R("tm-backups", ["/Volumes/*/Backups.backupdb", "/Volumes/*/*.backupbundle",
                     "/Volumes/*/*.sparsebundle"],
      "Backup Time Machine", "backup", JANGAN,
      "Cadangan Time Machine.", "Cadangan rusak.",
      "Kelola dari aplikasi Time Machine.", lock=True),
    R("system-library", "/Library", "Library sistem", "system", HATI,
      "Pengaturan & komponen untuk semua pengguna (driver, plugin, font).",
      "Aplikasi atau perangkat bisa berhenti berfungsi.", inherit=False, deletable=False),
    R("users", "/Users", "Folder pengguna", "docs", PERIKSA,
      "Folder rumah semua pengguna Mac ini.", inherit=False, deletable=False),
    R("home", "~", "Folder rumah Anda", "docs", PERIKSA,
      "Semua file & pengaturan milik akun Anda.", inherit=False, deletable=False),
    R("root", "/", "Disk utama", "system", JANGAN, "Akar dari semua file.",
      inherit=False),
]

RULES_BY_ID: Dict[str, Rule] = {r.id: r for r in RULES}

# Folder yang isinya boleh dibuang satu per satu (cache, log, file pribadi).
# Untuk aturan lain, yang boleh dibuang hanya folder itu sendiri atau anak
# langsungnya (mis. satu backup utuh, satu simulator utuh, satu .app utuh).
for _id in ("user-caches", "user-caches-item", "app-caches", "container-caches", "chrome-sw",
            "brew-cache", "vscode-cache", "npm-cache", "gradle", "maven", "cargo", "cocoapods",
            "conda-pkgs", "pycache", "next-build", "xcode-deriveddata", "xcode-devicelogs",
            "simulator-caches", "user-logs", "cores", "downloads", "desktop-docs",
            "media-folders", "installer", "archive", "video-file", "ios-updates"):
    RULES_BY_ID[_id].granular = True

# Paket yang isinya tidak boleh "ditafsirkan ulang" oleh aturan lain
# (mis. file .zip di dalam backup iPhone tetap bagian dari backup).
for _id in ("ios-backup", "simulator-devices", "simulator-runtimes", "xcode-archives",
            "vm-files", "app-bundle", "node-modules", "pods", "venv", "huggingface",
            "android-avd", "docker", "orbstack", "colima", "docker-linux", "steam",
            "garageband", "messages-attachments", "whatsapp", "telegram"):
    RULES_BY_ID[_id].lock = True

# Path yang tidak boleh dibuang apa pun aturannya.
PROTECTED_PATHS = {
    "/", "/System", "/Users", "/Applications", "/Library", "/private", "/usr", "/bin",
    "/sbin", "/etc", "/var", "/opt", "/Volumes", "/home", "/root",
}
PROTECTED_HOME_CHILDREN = {
    "Library", "Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures",
    "Public", "Applications", ".Trash",
}


def glob_to_regex(pattern: str) -> str:
    """Ubah pola glob (sudah tanpa ``~``) menjadi regex tanpa anchor."""
    out: List[str] = []
    i = 0
    n = len(pattern)
    while i < n:
        if pattern.startswith("**/", i):
            out.append("(?:.*/)?")
            i += 3
        elif pattern.startswith("/**", i) and i + 3 == n:
            out.append("(?:/.*)?")
            i += 3
        elif pattern[i] == "*":
            out.append("[^/]*")
            i += 1
        elif pattern[i] == "?":
            out.append("[^/]")
            i += 1
        else:
            out.append(re.escape(pattern[i]))
            i += 1
    return "".join(out)


class RuleMatcher:
    """Mencocokkan path dengan daftar aturan memakai satu regex gabungan
    (jauh lebih cepat daripada mencoba aturan satu per satu)."""

    def __init__(self, home: Optional[str] = None, rules: Optional[List[Rule]] = None):
        self.home = (home or os.path.expanduser("~")).rstrip("/") or "/"
        self.rules = rules if rules is not None else RULES
        parts: List[str] = []
        self._group_rule: List[Rule] = []
        for rule in self.rules:
            for pat in rule.patterns:
                if pat == "~" or pat.startswith("~/"):
                    pat = self.home + pat[1:]
                rx = glob_to_regex(pat)
                idx = len(self._group_rule)
                parts.append("(?P<g%d>%s)" % (idx, rx))
                self._group_rule.append(rule)
        self._regex = re.compile("^(?:%s)$" % "|".join(parts), re.IGNORECASE)

    def match(self, path: str) -> Optional[Rule]:
        m = self._regex.match(path)
        if not m:
            return None
        return self._group_rule[int(m.lastgroup[1:])]

    def resolve(self, path: str, parent_rule: Optional[Rule],
                parent_inherited: bool = False) -> Tuple[Optional[Rule], bool]:
        """Aturan efektif untuk ``path``: (rule, inherited?)."""
        if parent_rule is not None and parent_rule.lock:
            return parent_rule, True
        own = self.match(path)
        if own is not None:
            return own, False
        if parent_rule is not None and parent_rule.inherit:
            return parent_rule, True
        return None, False

    def display(self, path: str) -> str:
        if path == self.home:
            return "~"
        if self.home != "/" and path.startswith(self.home + "/"):
            return "~" + path[len(self.home):]
        return path

    def is_protected(self, path: str) -> bool:
        path = path.rstrip("/") or "/"
        if path in PROTECTED_PATHS or path == self.home:
            return True
        parent, name = os.path.split(path)
        if parent == self.home and name in PROTECTED_HOME_CHILDREN:
            return True
        # Folder rumah pengguna lain (/Users/nama)
        if parent in ("/Users", "/home"):
            return True
        return False


def can_delete(rule: Optional[Rule], depth: int = 0) -> bool:
    """depth = seberapa dalam item ini di bawah folder yang cocok dengan aturan
    (0 = folder itu sendiri, 1 = anak langsung, dst)."""
    if rule is None:
        return True
    if not rule.deletable:
        return False
    return rule.granular or depth <= 1


def rule_info(rule: Optional[Rule], inherited: bool = False, depth: int = 0) -> dict:
    if rule is None:
        return {
            "id": None,
            "title": "Tidak dikenali",
            "category": "other",
            "categoryLabel": CATEGORIES["other"],
            "safety": UNKNOWN,
            "safetyLabel": SAFETY_LABELS[UNKNOWN],
            "why": "Aplikasi ini belum mengenali folder/file ini.",
            "effect": "Tidak diketahui — periksa isinya sendiri sebelum menghapus.",
            "how": "Buka di Finder dan lihat isinya. Bila ragu, jangan dihapus.",
            "command": "",
            "mode": "self",
            "deletable": True,
            "inherited": False,
        }
    d = rule.to_dict()
    d["inherited"] = inherited
    if rule.deletable and not can_delete(rule, depth):
        d["deletable"] = False
        d["partOf"] = True   # bagian dalam sebuah paket: buang paketnya utuh
    if inherited:
        # Isi di dalam folder yang dikenali: buang item itu sendiri, bukan isinya.
        d["mode"] = "self"
    return d


IS_MAC = sys.platform == "darwin"
