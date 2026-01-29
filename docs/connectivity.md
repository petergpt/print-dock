# PrintDockKit (Connectivity)

PrintDockKit provides the BLE connectivity layer for the Polaroid Hi·Print 2×3.

## Core API

```swift
import PrintDockKit

let client = HiPrintBLEClient(targetNamePrefix: "Hi-Print")
client.connect()

// Later, after connected:
client.send(jpeg: jpegData, paceMs: 2)
```

## Notes

- The printer auto-sleeps quickly. Expect to power it on right before connecting.
- The client connects to the first device whose name contains `targetNamePrefix`.
- `lastStatus` is polled once per second once connected.

## Troubleshooting

- **Bluetooth permissions**: the app must declare Bluetooth usage strings.
- **No device found**: confirm the printer is in pairing mode and within range.
- **Send fails**: ensure the printer is connected and not asleep.
