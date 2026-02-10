# AI Agent Connectivity + Print Flow Deep Dive

This document is the technical handoff for troubleshooting and extending the Hi-Print BLE stack in this repo.
It is intentionally implementation-heavy and maps directly to source files.

## Scope

- Connectivity layer: `Sources/PrintDockKit`
- App orchestration: `Sources/PrintDockApp`
- CLI orchestration: `Sources/PrintDockCLI`
- Optional skill runner integration: `skills/surprise-print`

## Source Of Truth Files

- BLE client and state machine: `Sources/PrintDockKit/HiPrintBLEClient.swift`
- Status decoding: `Sources/PrintDockKit/PrinterStatus.swift`
- Packet protocol framing: `Sources/PrintDockKit/HiPrintPacketizer.swift`
- Protocol constants and UUIDs: `Sources/PrintDockKit/HiPrintConstants.swift`
- Image rendering pipeline: `Sources/PrintDockKit/ImagePipeline.swift`
- Queue model: `Sources/PrintDockKit/PrintQueue.swift`
- App queue/send orchestration: `Sources/PrintDockApp/AppModel.swift`
- CLI behavior: `Sources/PrintDockCLI/PrintDockCLI.swift`
- CLI Bluetooth plist injection: `Package.swift`, `Sources/PrintDockCLI/Info.plist`

## End-To-End Flow

1. Input image is normalized and rendered to protocol size `640x1024` in `ImagePipeline`.
2. JPEG payload is packetized into one 10-byte header packet + N data frames (`HiPrintPacketizer`).
3. `HiPrintBLEClient` connects, discovers printer service/chars, then writes all packets to write characteristic (without response).
4. Completion is status-driven: packet transfer reaching 100% is not success by itself.
5. Send is marked complete only after post-transfer status confirms printer readiness again.

## BLE Contract

- Service UUID: `C3D1E0CB-9C4E-434E-A915-12097CD84F81`
- Write characteristic UUID: `C3D1E0CC-9C4E-434E-A915-12097CD84F81`
- Read/status characteristic UUID: `C3D1E0CD-9C4E-434E-A915-12097CD84F81`
- Writes use `.withoutResponse`.

From `HiPrintConstants`, payload target is fixed at:
- Width: `640`
- Height: `1024`

## Discovery + Connection Strategy

`HiPrintBLEClient.connect()` behavior:

1. If Bluetooth is already on, starts scan immediately.
2. If not, sets `.connecting`; actual scan begins when central state becomes `.poweredOn`.

Scan strategy:

1. Preferred peripheral reconnect path:
   - Reads `UserDefaults` key `PrintDock.PreferredPeripheral.<prefix-lowercased>`.
   - If found via `retrievePeripherals(withIdentifiers:)`, connects directly.
2. Service-filtered scan for `4s` (`filteredScanWindow`).
3. If no hit, fallback scan without service filter using name matching.
4. Total scan timeout is `12s`.

Connection handshake:

1. Discover service UUID.
2. Discover write/read characteristics.
3. Set state `.connected(name:)`.
4. Start status polling every `1s`.
5. Trigger immediate status read.

## Status Payload Decoding

`PrinterStatus` uses raw bytes and decodes:

- `phaseCode` at byte index `2`
- `issueCode` at byte index `3`

Phase mapping:

- `0x00` -> preparing
- `0x01` -> layer 1
- `0x02` -> layer 2
- `0x03` -> layer 3
- `0x07` -> ready
- `0xFF` -> processing
- other -> `phase 0xNN`

Issue mapping:

- `0x00` -> none
- `0x09` -> `printer attention (0x09)`
- other non-zero -> `issue 0xNN`

Derived flags:

- `isIssueActive`: issue code is non-zero
- `isReadyForNextJob`: phase is `0x07` and no issue
- `isProcessingPrint`: phase is one of `0x00,0x01,0x02,0x03,0xFF`

## Image Pipeline Details

`ImagePipeline.makePrintableJPEG(...)`:

1. Converts `NSImage` to `CGImage`.
2. Renders to exactly `640x1024` on white background.
3. Uses cover fit (`max(scaleX, scaleY)`), then multiplies by `zoom`.
4. Clamps offset to avoid blank regions.
5. Encodes JPEG via `CGImageDestination` (quality default from caller).

App defaults:

- `paceMs = 12`
- `jpegQuality = 0.98`
- `sendTimeout = 90`

## Packet Protocol Format

Header packet (`10` bytes):

- bytes `[0..2]`: payload length (24-bit big-endian)
- bytes `[3..9]`: fixed tail `[00 00 00 01 00 00 00]`

Data frame packet:

- bytes `[0..2]`: payload offset (24-bit big-endian)
- byte `[3]`: flags (`0x00`)
- byte `[4]`: chunk length (`1..200`)
- bytes `[5..]`: payload bytes

Chunk sizing:

- `maxWriteLength = peripheral.maximumWriteValueLength(.withoutResponse)`
- frame overhead is `5`, so `maxDataBytes = min(200, maxWriteLength - 5)`

## Send State Machine (Critical)

Pre-send rejection conditions:

- Empty JPEG
- Not connected
- Missing transport (`peripheral` or `writeChar`)
- Another send already active
- Last status reports active issue
- Last status reports printer busy/processing

Current behavior note:

- If `lastStatus` is still `nil` right after connect, send is allowed to start.
- Readiness is then enforced in the post-transfer phase (issue/fault still fails), but this can delay failure feedback.

Transfer phase:

1. Build packet list, set `isSending = true`, `sendOutcome = nil`, `sendProgress = 0`.
2. Schedule send timeout.
3. Write packets with pacing:
   - `pace <= 0`: burst while `canSendWriteWithoutResponse`.
   - `pace > 0`: timer-based one packet every `paceMs`.
4. `sendProgress` tracks packet-transfer progress only.

Post-transfer phase:

1. On last packet write, call `markPacketTransferComplete()`:
   - sets `sendProgress = 1.0`
   - stores `transferCompletedAt`
   - does not complete outcome yet
2. `evaluateSendOutcomeFromStatus()` waits for a fresh status update timestamped after transfer completion.
3. Outcome rules:
   - issue active -> `sendOutcome = .failed`
   - processing phase -> keep waiting
   - ready phase with no issue -> `sendOutcome = .completed`

This split prevents false positives where 100% packet transfer occurred but printer then faulted.

## App Queue Semantics

`AppModel` enqueues image snapshots and serialized JPEG payloads per job ID.

Rules:

- Only one active hardware send at a time (`currentJob`).
- Additional jobs remain in `pendingJobs` list.
- Queue state only moves to `.completed` on `sendOutcome == .completed`.
- Queue is not completed on progress `1.0` alone.
- On completion/failure, job payload is removed, then next queued job starts.

## CLI Semantics

`printdock` commands:

- `scan`: connect probe only.
- `status`: prints raw hex + decoded `PHASE`, `ISSUE`, `READY`.
- `print`: render JPEG, send, wait for `sendOutcome`.

Print completion in CLI:

- Timeout floor is enforced at `90s`.
- Success requires `sendOutcome == .completed` (not just progress 100%).
- Output contains `PRINT_DONE` only on verified completion.

## macOS Bluetooth Permission Mechanics

Two paths are intentionally covered:

1. App packaging:
   - `scripts/package_app.sh` writes Bluetooth usage keys into app `Info.plist`.
2. CLI binary:
   - `Package.swift` injects `Sources/PrintDockCLI/Info.plist` into the executable via linker `-sectcreate`.

Skill integration note:

- `skills/surprise-print/scripts/run_surprise_print.sh` wraps `printdock` inside a temporary `.app` and runs it via `open -W`.
- This is used to keep macOS permission behavior predictable and capture stdout/stderr logs.

## Failure Signatures And Fast Triage

### `Scan timed out`

Meaning:
- Device not discovered in filtered + fallback scan window.

Checks:
- Printer awake and close enough.
- Prefix matches device name (`Hi-Print` by default).

### `Print rejected: Printer needs attention: printer attention (0x09)`

Meaning:
- Status issue byte is non-zero (`0x09` currently labeled generic attention).

Checks:
- Cartridge or media path issue.
- Wait for phase to return ready and issue to return none.

### `Print rejected: Printer is busy (...)`

Meaning:
- Printer still processing previous job.

Checks:
- Poll status until `READY true`.

### Progress hits 100% then failure

Meaning:
- Packet transfer completed, but post-transfer status reported fault or never returned ready before timeout.

Checks:
- Inspect status polling and issue byte after transfer.

### `No status received`

Meaning:
- Connected at BLE level but read characteristic data not arriving.

Checks:
- Characteristic discovery succeeded.
- Polling active.
- Permissions path (app/CLI plist) valid.

### Surprise skill print skipped intentionally

Meaning:
- Runner readiness precheck saw `READY false` or status probe failure.

Artifacts:
- `skills/surprise-print/output/.../printdock.stdout.log`
- `skills/surprise-print/output/.../printdock.stderr.log`

## Safe Debug Pattern (Minimize Wasted Prints)

1. Run status only and verify:
   - `READY true`
   - `ISSUE 0x00 none`
2. Send one print job only after status is healthy.
3. If failure occurs, inspect post-transfer status before retrying.

Do not loop print retries blindly; consume status evidence first.

## Extending The Stack

When adding protocol handling:

1. Add/adjust decode logic in `PrinterStatus`.
2. Add unit tests in `Tests/PrintDockKitTests/PrinterStatusTests.swift`.
3. Keep send completion status-driven in `HiPrintBLEClient`.
4. Keep app queue completion coupled to `sendOutcome`.

When changing packet framing:

1. Update `HiPrintPacketizer`.
2. Update `Tests/PrintDockKitTests/PacketizerTests.swift`.
3. Validate against printer behavior with one controlled real print.
