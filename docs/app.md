# Print Dock App

A SwiftUI macOS app built on PrintDockKit.

## Run in Xcode

1) Open `Package.swift` in Xcode
2) Select the **PrintDockApp** target
3) Run

## Package a clickable .app

```
./scripts/package_app.sh
open dist/PrintDock.app
```

## Bluetooth permissions

The packaging script embeds required Bluetooth usage strings in the app Info.plist.
