#!/bin/bash
# Membuat installer DMG: macos/build/MacCleaner-<versi>.dmg
#
# Isinya MacCleaner.app + pintasan ke folder Aplikasi (cukup seret).
#
# Variabel (semua opsional):
#   SIGN_IDENTITY   "Developer ID Application: Nama Anda (TEAMID)"
#   NOTARY_PROFILE  nama profil dari `xcrun notarytool store-credentials` (untuk di Mac sendiri)
#   APPLE_ID, APPLE_APP_PASSWORD, APPLE_TEAM_ID
#                   alternatif NOTARY_PROFILE (dipakai di GitHub Actions)
#
# Contoh di Mac Anda:
#   xcrun notarytool store-credentials maccleaner \
#       --apple-id you@example.com --team-id ABCDE12345
#   SIGN_IDENTITY="Developer ID Application: Nama Anda (ABCDE12345)" \
#   NOTARY_PROFILE=maccleaner ./scripts/make_dmg.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/macos/build"
VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$ROOT/maccleaner/__init__.py")"
DMG="$OUT/MacCleaner-$VERSION.dmg"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

"$ROOT/scripts/build_mac_app.sh"

STAGE="$(mktemp -d)"
SRC="$STAGE/MacCleaner"
mkdir -p "$SRC"
ditto "$OUT/MacCleaner.app" "$SRC/MacCleaner.app"
ln -s /Applications "$SRC/Aplikasi"

rm -f "$DMG"
hdiutil create -volname "MacCleaner $VERSION" -srcfolder "$SRC" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
echo "DMG dibuat: $DMG"

if [ -z "$SIGN_IDENTITY" ]; then
  echo
  echo "Catatan: DMG belum ditandatangani Developer ID. Di Mac lain akan muncul peringatan"
  echo "Gatekeeper. Set SIGN_IDENTITY (dan kredensial notarisasi) untuk installer resmi."
  exit 0
fi

codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

NOTARY_ARGS=()
if [ -n "${NOTARY_PROFILE:-}" ]; then
  NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${APPLE_APP_PASSWORD:-}" ] && [ -n "${APPLE_TEAM_ID:-}" ]; then
  NOTARY_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
fi

if [ ${#NOTARY_ARGS[@]} -eq 0 ]; then
  echo "Ditandatangani, tapi belum dinotarisasi (NOTARY_PROFILE / APPLE_ID belum diset)."
  exit 0
fi

echo "Mengirim ke Apple untuk notarisasi (biasanya 1–10 menit)…"
RESULT="$(xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait --output-format json)"
echo "$RESULT"
STATUS="$(echo "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("status",""))')"
if [ "$STATUS" != "Accepted" ]; then
  ID="$(echo "$RESULT" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("id",""))')"
  echo "Notarisasi gagal ($STATUS). Log dari Apple:"
  [ -n "$ID" ] && xcrun notarytool log "$ID" "${NOTARY_ARGS[@]}" || true
  exit 1
fi

xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
echo
echo "Siap dibagikan: $DMG"
