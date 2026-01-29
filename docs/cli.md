# printdock CLI

The CLI is a lightweight wrapper around PrintDockKit.

## Commands

```
printdock scan [--prefix "Hi-Print"] [--timeout 12]
printdock status [--prefix "Hi-Print"] [--timeout 12]
printdock print /path/to/photo.jpg [--prefix "Hi-Print"] [--timeout 30] [--pace 2]
```

## Examples

```
swift run printdock scan
swift run printdock status
swift run printdock print ~/Pictures/photo.jpg
```

## Notes

- The CLI connects to the first matching printer name.
- Printing uses a fixed 2×3 portrait output and centered placement.
