#!/bin/bash
# Membuat dist/MacCleaner.app — aplikasi yang bisa ditaruh di folder Aplikasi
# dan dibuka dari Launchpad/Dock. Memakai Python 3 bawaan macOS
# (Command Line Tools), tanpa dependensi tambahan.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/MacCleaner.app"
VERSION="$(python3 -c 'import sys; sys.path.insert(0, "'"$ROOT"'"); import maccleaner; print(maccleaner.__version__)')"

# Bangun di folder sementara lalu ganti yang lama.
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/MacCleaner.app/Contents/MacOS" "$STAGE/MacCleaner.app/Contents/Resources"
cp -R "$ROOT/maccleaner" "$STAGE/MacCleaner.app/Contents/Resources/maccleaner"
find "$STAGE" -name '__pycache__' -type d -prune -exec rm -r {} +

cat > "$STAGE/MacCleaner.app/Contents/MacOS/MacCleaner" <<'EOF'
#!/bin/bash
RES="$(cd "$(dirname "$0")/../Resources" && pwd)"
LOG="$HOME/Library/Logs/MacCleaner.log"
PY="$(command -v python3 || echo /usr/bin/python3)"
cd "$RES" || exit 1
exec "$PY" -m maccleaner app --auto-exit >>"$LOG" 2>&1
EOF
chmod +x "$STAGE/MacCleaner.app/Contents/MacOS/MacCleaner"

cat > "$STAGE/MacCleaner.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>MacCleaner</string>
  <key>CFBundleDisplayName</key><string>MacCleaner</string>
  <key>CFBundleIdentifier</key><string>app.maccleaner.local</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleExecutable</key><string>MacCleaner</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>10.15</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

mkdir -p "$ROOT/dist"
if [ -d "$APP" ]; then mv "$APP" "$STAGE/old.app"; fi
mv "$STAGE/MacCleaner.app" "$APP"
echo "Selesai: $APP"
echo "Seret ke folder Aplikasi. Saat dibuka pertama kali: klik kanan → Buka (aplikasi belum ditandatangani)."
