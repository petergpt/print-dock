#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

swift build -c release

APP_DIR="$ROOT/dist/PrintDock.app"
BIN="$ROOT/.build/release/PrintDock"
ICON="$ROOT/assets/PrintDock.icns"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN" "$APP_DIR/Contents/MacOS/PrintDock"

if [ ! -f "$ICON" ]; then
  "$ROOT/scripts/build_icon.sh"
fi

if [ -f "$ICON" ]; then
  cp "$ICON" "$APP_DIR/Contents/Resources/PrintDock.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Print Dock</string>
  <key>CFBundleDisplayName</key>
  <string>Print Dock</string>
  <key>CFBundleIdentifier</key>
  <string>com.printdock.studio</string>
  <key>CFBundleVersion</key>
  <string>0.2.0</string>
  <key>CFBundleShortVersionString</key>
  <string>0.2.0</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>PrintDock</string>
  <key>CFBundleIconFile</key>
  <string>PrintDock.icns</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSBluetoothAlwaysUsageDescription</key>
  <string>Print Dock needs Bluetooth to connect to your Hi·Print printer.</string>
  <key>NSBluetoothPeripheralUsageDescription</key>
  <string>Print Dock needs Bluetooth to connect to your Hi·Print printer.</string>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "Built: $APP_DIR"
