#!/bin/bash
# Klik dua kali file ini di Finder untuk membuka MacCleaner.
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 belum terpasang."
  echo "Jalankan:  xcode-select --install   lalu coba lagi."
  read -r -p "Tekan Enter untuk menutup…"
  exit 1
fi
exec python3 -m maccleaner app "$@"
