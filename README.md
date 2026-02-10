# Print Dock (macOS)

Print Dock is an open-source macOS app and connectivity kit for the Polaroid Hi·Print 2×3 printer.

This repo is intentionally split so each module can be used independently.

## Choose your path

### 1) Connectivity only (library + CLI)
Use **PrintDockKit** to discover/connect to the printer and send print jobs.

- Docs: `docs/connectivity.md`
- API entry point: `PrintDockKit/HiPrintBLEClient`
- CLI docs: `docs/cli.md`

### 2) Full app (Print Dock)
A native SwiftUI app built on top of PrintDockKit.

- Docs: `docs/app.md`
- Build/Package: `scripts/package_app.sh`

### 3) Surprise Print skill
An end-to-end “news to image to print” workflow script that can call `printdock` safely with readiness checks.

- Module docs: `skills/surprise-print/README.md`

## Repository layout

- `Sources/PrintDockKit` — BLE client, packetizer, image pipeline
- `Sources/PrintDockApp` — SwiftUI app
- `Sources/PrintDockCLI` — command-line tool
- `skills/surprise-print` — optional surprise-print workflow
- `Tests/PrintDockKitTests` — unit tests
- `scripts/` — packaging + validation
- `assets/` — icon source + generated assets

## Quick start

### Build the app
```
swift build
```

### Run the app (Xcode)
Open the package in Xcode and run the **PrintDockApp** target.

### Package a clickable .app
```
./scripts/package_app.sh
open dist/PrintDock.app
```

### Use the CLI
```
swift run printdock scan
swift run printdock status
swift run printdock print /path/to/photo.jpg
```

## Validation

```
./scripts/verify.sh
```

This runs `swift build` and, if Xcode is installed, `swift test`.

## License

MIT — see `LICENSE`.
