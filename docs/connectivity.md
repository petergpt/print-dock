# PrintDockKit (Connectivity)

PrintDockKit provides the BLE connectivity layer for the Polaroid Hi·Print 2×3.

## Core API

```swift
import PrintDockKit

let client = HiPrintBLEClient(targetNamePrefix: "Hi-Print")
client.connect()

// Later, after connected:
switch client.send(jpeg: jpegData, paceMs: 12) {
case .started:
    break
case .rejected(let reason):
    print("Could not start send: \(reason)")
}
```

## Notes

- The printer auto-sleeps quickly. Expect to power it on right before connecting.
- Connect uses a service-filtered scan first, then falls back to name matching.
- The last successful peripheral UUID is reused to speed up reconnects.
- `lastStatus` is polled once per second once connected and GATT-ready.

## Troubleshooting

- **Bluetooth permissions**: the app must declare Bluetooth usage strings.
- **No device found**: confirm the printer is in pairing mode and within range.
- **Send rejected**: ensure the connection state is `connected`, printer status is ready, and no printer issue code is active.
