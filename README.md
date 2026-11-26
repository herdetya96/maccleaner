# MacCleaner

Aplikasi untuk mencari tahu **kenapa disk Mac penuh** dan **apa yang aman dihapus**.

- **Ringkasan Disk** — semua disk/volume beserta persentase terpakai dan status (aman / mulai penuh / kritis).
- **Kenapa penuh?** — diagram pemakaian per kategori (cache, file developer, backup iPhone, Docker, foto & video, dll) dan daftar temuan dalam bahasa sehari-hari.
- **Analisis Folder** — telusuri folder dari yang terbesar. Setiap folder/file diberi penjelasan:
  - apa isinya dan kenapa bisa besar,
  - apa yang terjadi kalau dihapus,
  - cara membersihkan yang benar (termasuk perintah Terminal bila ada).
- **Rekomendasi** — kandidat pembersihan yang dikelompokkan (DerivedData Xcode, cache aplikasi, `node_modules`, installer `.dmg`, backup iPhone lama, simulator, dll), lengkap dengan total ruang yang bisa dikosongkan.
- **File Besar** — 150 file tunggal terbesar beserta statusnya.

## Label keamanan

| Label | Arti |
|---|---|
| 🟢 **Aman dihapus** | Dibuat ulang otomatis atau tidak dibutuhkan lagi (cache, log, hasil build, installer). |
| 🟡 **Hati-hati** | Bisa dihapus, tapi ada akibatnya (backup iPhone, simulator iOS, VM, toolchain). |
| 🔵 **Periksa dulu** | File pribadi Anda — Anda yang memutuskan (Unduhan, Dokumen, video). |
| 🔴 **Jangan dihapus** | Sistem macOS, iCloud Drive, Perpustakaan Foto, Mail — menghapus manual bisa merusak data. |

## Pengamanan

- File **tidak pernah dihapus permanen**: semua dipindah ke **Sampah** (lewat Finder, jadi bisa "Kembalikan"). Ruang disk baru benar-benar kosong setelah Sampah dikosongkan, dan untuk itu ada tombol tersendiri dengan konfirmasi.
- Item berlabel *Jangan dihapus* tidak bisa dibuang dari aplikasi.
- Folder penting (`/System`, `~/Library`, `~/Documents`, folder rumah, dll) selalu dilindungi.
- Isi iCloud Drive / Dropbox / Google Drive tidak bisa dibuang, karena menghapusnya juga menghapus file dari cloud dan semua perangkat Anda. Aplikasi menjelaskan cara "Hapus Unduhan" sebagai gantinya.
- Satu file di **dalam** sebuah paket (misalnya backup iPhone, `.app`, simulator, `node_modules`) tidak bisa dibuang sendirian, karena itu bisa merusak paketnya. Yang bisa dibuang hanya paketnya secara utuh.
- Docker, simulator runtime, lampiran iMessage, WhatsApp/Telegram, dan sejenisnya diarahkan ke cara resmi (misalnya `docker system prune`) dan tidak dihapus filenya.
- Server hanya berjalan di `127.0.0.1` dengan token acak, jadi situs web lain tidak bisa memerintahkannya.

## Dua versi

| | Desktop app | Versi web (Python) |
|---|---|---|
| Lokasi | `macos/` + `ui/` | `maccleaner/` |
| Tampilan | Jendela Mac dengan tampilan coss ui, menu, mode gelap | Di browser |
| Butuh | macOS 13 Ventura atau lebih baru | Python 3 (Mac/Linux) |
| Mode terminal | – | `python3 -m maccleaner scan ~` |

Keduanya memakai basis pengetahuan yang sama. Aturan di Swift (`macos/Sources/MacCleanerCore/RuleData.swift`) dibuat otomatis dari `maccleaner/rules.py`:

```bash
python3 scripts/gen_swift_rules.py
```

## Desktop app

Aplikasi Mac asli (jendela, menu, ikon, DMG) dengan tampilan dari **[coss ui](https://coss.com/ui)**, design system Cal.com berbasis React + Base UI + Tailwind. Tampilan ada di folder `ui/` dan dimuat di dalam jendela lewat WKWebView. Semua logika (pemindai, aturan, buang ke Sampah) berjalan di Swift (`macos/Sources/MacCleanerCore`) tanpa server dan tanpa internet.

### Pasang dari DMG

Buka `MacCleaner-x.y.z.dmg`, lalu seret **MacCleaner** ke pintasan **Aplikasi**. Selesai.

- Rilis resmi ada di halaman **Releases** (dibuat otomatis saat tag `v*` di-push).
- Build terbaru dari setiap push ada di tab **Actions** → run terbaru → artefak **MacCleaner-DMG**.

DMG yang ditandatangani Developer ID dan dinotarisasi langsung bisa dibuka tanpa peringatan. Kalau DMG-nya *belum* ditandatangani (secrets belum diisi), saat pertama kali membuka: klik kanan → **Buka**.

### Menyiapkan tanda tangan & notarisasi (sekali saja)

Butuh akun Apple Developer (berbayar).

1. **Buat sertifikat Developer ID Application**
   Xcode → Settings → Accounts → pilih tim → **Manage Certificates…** → **+** → **Developer ID Application**.
2. **Ekspor sertifikat sebagai .p12**
   Buka **Keychain Access** → My Certificates → klik kanan "Developer ID Application: …" → **Export…** → simpan sebagai `.p12` dengan kata sandi.
3. **Buat app-specific password** di [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords.
4. **Cari Team ID** di [developer.apple.com/account](https://developer.apple.com/account) → Membership details (10 karakter, misalnya `ABCDE12345`).
5. **Isi GitHub Secrets** di repo → Settings → Secrets and variables → Actions → *New repository secret*:

   | Secret | Isi |
   |---|---|
   | `MACOS_CERT_P12` | isi file .p12 dalam base64 (perintah di bawah) |
   | `MACOS_CERT_PASSWORD` | kata sandi .p12 dari langkah 2 |
   | `APPLE_ID` | email Apple ID akun developer |
   | `APPLE_APP_PASSWORD` | app-specific password dari langkah 3 |
   | `APPLE_TEAM_ID` | Team ID dari langkah 4 |

   Salin .p12 sebagai base64 ke clipboard:

   ```bash
   base64 -i DeveloperID.p12 | pbcopy
   ```

6. **Terbitkan rilis**: CI menandatangani, menotarisasi, dan mengunggah DMG ke Releases.

   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   ```

Jangan pernah commit file .p12 atau kata sandi ke repo. Simpan hanya di GitHub Secrets.

### Build DMG di Mac sendiri

Butuh Xcode atau Command Line Tools (Swift 5.9+) dan **Node.js 20+** (untuk membangun tampilan).

Tanpa tanda tangan (untuk dicoba sendiri):

```bash
./scripts/make_dmg.sh
```

Dengan tanda tangan + notarisasi. Simpan kredensial notarisasi ke Keychain sekali saja:

```bash
xcrun notarytool store-credentials maccleaner --apple-id EMAIL_ANDA --team-id TEAM_ID_ANDA
```

Lalu:

```bash
SIGN_IDENTITY="Developer ID Application: Nama Anda (TEAM_ID_ANDA)" NOTARY_PROFILE=maccleaner ./scripts/make_dmg.sh
```

Hasilnya `macos/build/MacCleaner-<versi>.dmg`. Nama identitas persisnya bisa dilihat dengan `security find-identity -v -p codesigning`.

Untuk mengembangkan, buka folder `macos/` (berisi `Package.swift`) di Xcode, lalu Run.

Fitur khusus desktop app:
- Ruang disk dihitung persis seperti Finder, termasuk ruang *purgeable*.
- Buang ke Sampah memakai API Finder, jadi item bisa "Kembalikan".
- Tombol pintasan ke pengaturan **Akses Disk Penuh** bila izinnya belum diberikan.
- Pindai folder mana pun (⌘O), folder rumah (⌘R), atau seluruh disk (⇧⌘R); pindah halaman dengan ⌘1–⌘4.

### Mengembangkan tampilan (coss ui)

Tampilan memakai API yang sama dengan server Python, jadi bisa dikembangkan & dicoba di browser di OS apa pun:

```bash
cd ui && npm install && npm run build
```

```bash
python3 -m maccleaner app --ui-dir ui/dist
```

Komponen coss ui ada di `ui/src/components/ui/` (disalin dari [github.com/cosscom/ui](https://github.com/cosscom/ui), lisensi MIT). Halaman aplikasi ada di `ui/src/views/`.

## Cara menjalankan versi web

Hanya butuh **Python 3**, yang ada di macOS setelah Command Line Tools terpasang (`xcode-select --install`). Tidak ada dependensi tambahan.

**Cara termudah:** klik dua kali `MacCleaner.command` di Finder. Aplikasi akan terbuka di browser.

Atau lewat Terminal:

```bash
python3 -m maccleaner
```

Laporan langsung di Terminal, tanpa browser:

```bash
python3 -m maccleaner disks
```

```bash
python3 -m maccleaner scan ~
```

### Jadikan aplikasi `.app`

```bash
./scripts/build_app.sh
```

Hasilnya `dist/MacCleaner.app`. Seret ke folder **Aplikasi**. Saat dibuka pertama kali: klik kanan → **Buka** (aplikasi belum ditandatangani Apple). Versi `.app` berhenti sendiri sekitar 2 menit setelah tab browser ditutup.

### Akses Disk Penuh (disarankan)

macOS melindungi folder seperti Mail, Pesan, dan Safari. Agar ukuran yang dihitung lengkap, beri izin:
**Pengaturan Sistem → Privasi & Keamanan → Akses Disk Penuh** → tambahkan **Terminal** (atau MacCleaner.app).
Aplikasi menampilkan jumlah folder yang tidak bisa dibaca bila izin ini belum diberikan.

## Kenapa angka di sini berbeda dengan Finder?

- **Data sistem / ruang "tak terbaca"**: snapshot Time Machine lokal, swap (memori virtual), dan file sistem yang terkunci tidak bisa dipindai. Saat memindai *Seluruh disk*, selisihnya ditampilkan sebagai "Data sistem / tak terbaca".
- **Ruang "dapat dibersihkan" (purgeable)**: Finder menghitungnya sebagai ruang kosong, padahal masih terpakai sampai macOS membutuhkannya.
- Ukuran memakai satuan desimal (1 GB = 1.000.000.000 byte), sama seperti Finder.

## Struktur kode

| File | Isi |
|---|---|
| `maccleaner/rules.py` | Basis pengetahuan: ±80 aturan (cache, Xcode, Docker, iCloud, dll) dengan penjelasan & tingkat keamanan. Tambah aturan baru di sini. |
| `maccleaner/scanner.py` | Pemindai disk (ukuran nyata di disk, hardlink dihitung sekali, tidak menyeberang ke disk lain). |
| `maccleaner/disks.py` | Daftar volume (`diskutil` di macOS, `df` di Linux). |
| `maccleaner/trash.py` | Buang ke Sampah lewat Finder, dan kosongkan Sampah. |
| `maccleaner/server.py` | Server lokal + API JSON. |
| `maccleaner/web/` | Antarmuka versi web (HTML/CSS/JS tanpa library luar, mendukung mode gelap). |
| `ui/` | Antarmuka desktop app: React + coss ui + Tailwind (Vite). |

Desktop app (`macos/`):

| File | Isi |
|---|---|
| `Sources/MacCleanerCore/` | Logika inti tanpa UI: aturan, pemindai, rekomendasi, buang ke Sampah + pemeriksaan keamanan. |
| `Sources/MacCleaner/` | Jendela aplikasi, menu, WKWebView, dan jembatan API (`ApiBridge.swift`) untuk tampilan coss ui. |
| `Tests/MacCleanerCoreTests/` | Tes logika inti. |

## Tes

```bash
python3 -m unittest discover -s tests -v
```

```bash
cd macos && swift test
```
