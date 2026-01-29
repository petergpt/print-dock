#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ASSETS="$ROOT/assets"
ICONSET="$ASSETS/PrintDock.iconset"
BASE_PNG="$ASSETS/PrintDock-1024.png"
ICNS_OUT="$ASSETS/PrintDock.icns"

mkdir -p "$ASSETS"

GEN_SWIFT="$ROOT/scripts/_gen_icon.swift"
cat > "$GEN_SWIFT" <<'SWIFT'
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

let rect = NSRect(x: 0, y: 0, width: size, height: size)
let inset: CGFloat = 40
let bgRect = rect.insetBy(dx: inset, dy: inset)

let baseGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.36, green: 0.42, blue: 0.54, alpha: 1.0),
    NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.34, alpha: 1.0)
])!
let basePath = NSBezierPath(roundedRect: bgRect, xRadius: 220, yRadius: 220)
baseGradient.draw(in: basePath, angle: -90)

let innerRect = bgRect.insetBy(dx: 64, dy: 64)
let innerGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.28, alpha: 1.0),
    NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.18, alpha: 1.0)
])!
let innerPath = NSBezierPath(roundedRect: innerRect, xRadius: 150, yRadius: 150)
innerGradient.draw(in: innerPath, angle: 120)

let accent = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.18, alpha: 1.0)
let badgeRect = NSRect(x: innerRect.maxX - 185, y: innerRect.maxY - 185, width: 110, height: 110)
let badge = NSBezierPath(ovalIn: badgeRect)
accent.setFill()
badge.fill()

let stripeWidth: CGFloat = 36
let stripeHeight: CGFloat = 130
let stripeY = innerRect.minY + 32
let stripeX = innerRect.minX + 56
let stripeGap: CGFloat = 12
let colors = [
    NSColor(calibratedRed: 0.99, green: 0.20, blue: 0.25, alpha: 1.0),
    NSColor(calibratedRed: 0.99, green: 0.78, blue: 0.12, alpha: 1.0),
    NSColor(calibratedRed: 0.12, green: 0.86, blue: 0.60, alpha: 1.0)
]
for i in 0..<3 {
    let rect = NSRect(x: stripeX + CGFloat(i) * (stripeWidth + stripeGap), y: stripeY, width: stripeWidth, height: stripeHeight)
    let path = NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12)
    colors[i].setFill()
    path.fill()
}

if let symbol = NSImage(systemSymbolName: "printer.fill", accessibilityDescription: nil) {
    let config = NSImage.SymbolConfiguration(pointSize: 460, weight: .bold)
    if let sized = symbol.withSymbolConfiguration(config) {
        sized.isTemplate = true
        let symbolRect = NSRect(x: 0, y: 0, width: size, height: size).insetBy(dx: 200, dy: 200)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -10)
        shadow.shadowBlurRadius = 22
        shadow.set()
        NSColor.white.set()
        sized.draw(in: symbolRect, from: .zero, operation: .sourceAtop, fraction: 1.0)
        NSShadow().set()
    }
}

image.unlockFocus()

if let tiff = image.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    let outURL = URL(fileURLWithPath: "__BASE_PNG__")
    try png.write(to: outURL)
}
SWIFT

sed -i '' "s|__BASE_PNG__|$BASE_PNG|g" "$GEN_SWIFT"

swift "$GEN_SWIFT"

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

sips -z 16 16     "$BASE_PNG" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32     "$BASE_PNG" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$BASE_PNG" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64     "$BASE_PNG" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$BASE_PNG" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256   "$BASE_PNG" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$BASE_PNG" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512   "$BASE_PNG" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$BASE_PNG" --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$BASE_PNG" --out "$ICONSET/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET" -o "$ICNS_OUT"

rm -f "$ROOT/scripts/_gen_icon.swift"

echo "Icon built: $ICNS_OUT"
