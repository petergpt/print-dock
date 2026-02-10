# printdock CLI

The CLI is a lightweight wrapper around PrintDockKit.

## Commands

```
printdock scan [--prefix "Hi-Print"] [--timeout 12]
printdock status [--prefix "Hi-Print"] [--timeout 12]
printdock print /path/to/photo.jpg [--prefix "Hi-Print"] [--timeout 12] [--pace 12]
```

## Examples

```
swift run printdock scan
swift run printdock status
swift run printdock print ~/Pictures/photo.jpg
```

## Notes

- The CLI reconnects to the last successful printer when possible.
- Printing uses a fixed 2×3 portrait output and centered placement.
- Print completion waits at least 90 seconds internally, even if a smaller `--timeout` is passed.
