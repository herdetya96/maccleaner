#!/bin/bash
# Build aplikasi desktop SwiftUI → macos/build/MacCleaner.app
# Butuh Xcode atau Command Line Tools (Swift 5.9+), macOS 13+.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/macos"
OUT="$PKG/build"
APP="$OUT/MacCleaner.app"
VERSION="$(sed -n 's/^__version__ = "\(.*\)"/\1/p' "$ROOT/maccleaner/__init__.py")"

cd "$PKG"
# Universal (Apple Silicon + Intel) bila didukung, selain itu arsitektur Mac ini.
if swift build -c release --arch arm64 --arch x86_64 >/dev/null 2>&1; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/MacCleaner"
else
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/MacCleaner"
fi

STAGE="$(mktemp -d)"
mkdir -p "$STAGE/MacCleaner.app/Contents/MacOS" "$STAGE/MacCleaner.app/Contents/Resources"
cp "$BIN" "$STAGE/MacCleaner.app/Contents/MacOS/MacCleaner"

cat > "$STAGE/MacCleaner.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacCleaner</string>
  <key>CFBundleDisplayName</key><string>MacCleaner</string>
  <key>CFBundleIdentifier</key><string>app.maccleaner.desktop</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleExecutable</key><string>MacCleaner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>id</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>MacCleaner meminta Finder untuk mengosongkan Sampah saat Anda menekan "Kosongkan Sampah".</string>
</dict>
</plist>
EOF

# Tanda tangan ad-hoc (wajib untuk Apple Silicon; tidak butuh akun developer).
codesign --force --deep --sign - "$STAGE/MacCleaner.app"

mkdir -p "$OUT"
if [ -d "$APP" ]; then mv "$APP" "$STAGE/old.app"; fi
mv "$STAGE/MacCleaner.app" "$APP"
echo "Selesai: $APP"
