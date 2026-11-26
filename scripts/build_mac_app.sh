#!/bin/bash
# Build aplikasi desktop SwiftUI → macos/build/MacCleaner.app
# Butuh Xcode atau Command Line Tools (Swift 5.9+), macOS 13+.
#
# Tanda tangan:
#   SIGN_IDENTITY="Developer ID Application: Nama Anda (TEAMID)" ./scripts/build_mac_app.sh
# Tanpa SIGN_IDENTITY, aplikasi ditandatangani ad-hoc (hanya untuk dipakai sendiri).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/macos"
OUT="$PKG/build"
APP="$OUT/MacCleaner.app"
VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$ROOT/maccleaner/__init__.py")"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

cd "$PKG"
# Universal (Apple Silicon + Intel) bila didukung, selain itu arsitektur Mac ini.
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacCleaner"
  echo "Build universal (arm64 + x86_64)."
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/MacCleaner"
fi

STAGE="$(mktemp -d)"
CONTENTS="$STAGE/MacCleaner.app/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/MacCleaner"

# Ikon: AppIcon.png (1024×1024) → AppIcon.icns
ICONSET="$STAGE/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$PKG/Resources/AppIcon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z $d $d "$PKG/Resources/AppIcon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"

cat > "$CONTENTS/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacCleaner</string>
  <key>CFBundleDisplayName</key><string>MacCleaner</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID:-app.maccleaner.desktop}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>MacCleaner</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>id</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MacCleaner ${VERSION}</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>MacCleaner meminta Finder untuk mengosongkan Sampah saat Anda menekan "Kosongkan Sampah".</string>
</dict>
</plist>
EOF

if [ -n "$SIGN_IDENTITY" ]; then
  echo "Tanda tangan: $SIGN_IDENTITY"
  # Hardened Runtime + timestamp: syarat notarisasi Apple.
  codesign --force --options runtime --timestamp \
    --entitlements "$PKG/MacCleaner.entitlements" \
    --sign "$SIGN_IDENTITY" "$STAGE/MacCleaner.app"
else
  echo "SIGN_IDENTITY kosong → tanda tangan ad-hoc (tidak bisa dinotarisasi)."
  codesign --force --sign - --entitlements "$PKG/MacCleaner.entitlements" "$STAGE/MacCleaner.app"
fi
codesign --verify --strict --verbose=2 "$STAGE/MacCleaner.app"

mkdir -p "$OUT"
if [ -d "$APP" ]; then mv "$APP" "$STAGE/old.app"; fi
mv "$STAGE/MacCleaner.app" "$APP"
echo "Selesai: $APP"
