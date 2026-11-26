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

## Cara menjalankan

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
| `maccleaner/web/` | Antarmuka (HTML/CSS/JS tanpa library luar, mendukung mode gelap). |

## Tes

```bash
python3 -m unittest discover -s tests -v
```
