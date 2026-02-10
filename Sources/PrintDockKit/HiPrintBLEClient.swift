import Foundation
@preconcurrency import CoreBluetooth
import Combine

public final class HiPrintBLEClient: NSObject, ObservableObject {
    @Published public private(set) var connectionState: ConnectionState = .idle
    @Published public private(set) var lastStatus: PrinterStatus?
    @Published public private(set) var sendProgress: Double = 0
    @Published public private(set) var sendOutcome: SendOutcome?
    @Published public private(set) var deviceName: String?
    @Published public private(set) var lastEvent: String = "idle"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var readChar: CBCharacteristic?
    private var statusTimer: Timer?
    private var scanTimeoutTimer: Timer?
    private var scanFallbackTimer: Timer?
    private var sendTimer: Timer?
    private var sendTimeoutTimer: Timer?

    private var pendingPackets: [Data] = []
    private var nextPacketIndex = 0
    private var paceMs: Int = 2
    private var isSending = false
    private var isFallbackScan = false
    private var transferCompletedAt: Date?
    private var sawPostTransferProcessing = false

    private let targetNamePrefix: String
    private let scanTimeout: TimeInterval = 12.0
    private let filteredScanWindow: TimeInterval = 4.0
    private let preferredPeripheralKey: String
    private var preferredPeripheralID: UUID?

    public init(targetNamePrefix: String = "Hi-Print") {
        self.targetNamePrefix = targetNamePrefix
        self.preferredPeripheralKey = "PrintDock.PreferredPeripheral.\(targetNamePrefix.lowercased())"
        if let saved = UserDefaults.standard.string(forKey: preferredPeripheralKey),
           let id = UUID(uuidString: saved) {
            self.preferredPeripheralID = id
        }
        super.init()
        self.central = CBCentralManager(delegate: self, queue: nil)
    }

    public var connectionStatePublisher: AnyPublisher<ConnectionState, Never> {
        $connectionState.eraseToAnyPublisher()
    }

    public var lastStatusPublisher: AnyPublisher<PrinterStatus?, Never> {
        $lastStatus.eraseToAnyPublisher()
    }

    public var sendProgressPublisher: AnyPublisher<Double, Never> {
        $sendProgress.eraseToAnyPublisher()
    }

    public var sendOutcomePublisher: AnyPublisher<SendOutcome?, Never> {
        $sendOutcome.eraseToAnyPublisher()
    }

    public var lastEventPublisher: AnyPublisher<String, Never> {
        $lastEvent.eraseToAnyPublisher()
    }

    public func connect() {
        lastEvent = "connect requested"
        if central.state == .poweredOn {
            startScan()
        } else {
            connectionState = .connecting
        }
    }

    public func disconnect() {
        failActiveSend(reason: "Disconnected")
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        cleanup()
        connectionState = .disconnected
        lastEvent = "disconnected"
    }

    @discardableResult
    public func send(jpeg: Data, paceMs: Int = 2, timeout: TimeInterval = 90) -> SendStartResult {
        guard !jpeg.isEmpty else {
            return .rejected(reason: "Image data is empty")
        }
        guard case .connected = connectionState else {
            return .rejected(reason: "Printer is not connected")
        }
        guard let peripheral, let writeChar else {
            return .rejected(reason: "Printer transport is not ready")
        }
        guard !isSending, transferCompletedAt == nil else {
            return .rejected(reason: "Another print is already in progress")
        }
        if let status = lastStatus {
            if status.isIssueActive {
                return .rejected(reason: "Printer needs attention: \(status.issueLabel)")
            }
            if status.isProcessingPrint {
                return .rejected(reason: "Printer is busy (\(status.phaseLabel))")
            }
        }

        let maxWriteLength = peripheral.maximumWriteValueLength(for: .withoutResponse)
        let maxDataBytes = max(1, min(200, maxWriteLength - 5))
        guard maxWriteLength > 5 else {
            return .rejected(reason: "BLE write MTU too small")
        }

        self.paceMs = max(0, paceMs)
        let packets = HiPrintPacketizer.packetize(payload: jpeg, maxDataBytes: maxDataBytes)
        pendingPackets = packets
        nextPacketIndex = 0
        isSending = true
        transferCompletedAt = nil
        sawPostTransferProcessing = false
        sendProgress = 0
        sendOutcome = nil
        lastEvent = "sending \(packets.count) packets"

        scheduleSendTimeout(seconds: timeout)
        sendNext(peripheral: peripheral, writeChar: writeChar)
        return .started
    }

    private func startScan() {
        cleanupScanState()
        connectionState = .scanning

        if let preferredPeripheralID,
           let known = central.retrievePeripherals(withIdentifiers: [preferredPeripheralID]).first {
            peripheral = known
            deviceName = known.name
            connectionState = .connecting
            lastEvent = "reconnecting known device"
            central.connect(known, options: nil)
            return
        }

        lastEvent = "scan started (service filter)"
        isFallbackScan = false
        central.scanForPeripherals(
            withServices: [HiPrintConstants.serviceUUID()],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        scanFallbackTimer = Timer.scheduledTimer(withTimeInterval: filteredScanWindow, repeats: false) { [weak self] _ in
            guard let self else { return }
            guard case .scanning = self.connectionState else { return }
            guard self.peripheral == nil else { return }

            self.central.stopScan()
            self.isFallbackScan = true
            self.lastEvent = "scan fallback (name match)"
            self.central.scanForPeripherals(
                withServices: nil,
                options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
            )
        }

        scanTimeoutTimer = Timer.scheduledTimer(withTimeInterval: scanTimeout, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.central.stopScan()
            if case .scanning = self.connectionState {
                self.connectionState = .failed(reason: "Scan timed out")
                self.lastEvent = "scan timeout"
            }
        }
    }

    private func cleanupScanState() {
        scanTimeoutTimer?.invalidate()
        scanTimeoutTimer = nil
        scanFallbackTimer?.invalidate()
        scanFallbackTimer = nil
        isFallbackScan = false
    }

    private func cleanup() {
        statusTimer?.invalidate()
        statusTimer = nil
        cleanupScanState()
        sendTimer?.invalidate()
        sendTimer = nil
        sendTimeoutTimer?.invalidate()
        sendTimeoutTimer = nil
        writeChar = nil
        readChar = nil
        peripheral = nil
        pendingPackets = []
        nextPacketIndex = 0
        isSending = false
        transferCompletedAt = nil
        sawPostTransferProcessing = false
        sendProgress = 0
    }

    private func scheduleSendTimeout(seconds: TimeInterval) {
        sendTimeoutTimer?.invalidate()
        sendTimeoutTimer = Timer.scheduledTimer(withTimeInterval: max(1, seconds), repeats: false) { [weak self] _ in
            guard let self else { return }
            self.failActiveSend(reason: "Send timed out")
        }
    }

    private func failActiveSend(reason: String) {
        guard isSending || transferCompletedAt != nil else { return }
        isSending = false
        sendTimer?.invalidate()
        sendTimer = nil
        sendTimeoutTimer?.invalidate()
        sendTimeoutTimer = nil
        pendingPackets = []
        nextPacketIndex = 0
        transferCompletedAt = nil
        sawPostTransferProcessing = false
        sendProgress = 0
        sendOutcome = .failed(reason: reason)
        lastEvent = "send failed: \(reason)"
    }

    private func completeActiveSend() {
        guard isSending || transferCompletedAt != nil else { return }
        isSending = false
        sendTimer?.invalidate()
        sendTimer = nil
        sendTimeoutTimer?.invalidate()
        sendTimeoutTimer = nil
        pendingPackets = []
        nextPacketIndex = 0
        transferCompletedAt = nil
        sawPostTransferProcessing = false
        sendProgress = 1.0
        sendOutcome = .completed
        lastEvent = "send complete"
    }

    private func markPacketTransferComplete() {
        guard isSending else { return }
        isSending = false
        sendTimer?.invalidate()
        sendTimer = nil
        pendingPackets = []
        nextPacketIndex = 0
        sendProgress = 1.0
        transferCompletedAt = Date()
        lastEvent = "packet transfer complete"
        evaluateSendOutcomeFromStatus()
    }

    private func evaluateSendOutcomeFromStatus() {
        guard let transferCompletedAt else { return }
        guard sendOutcome == nil else { return }
        guard let status = lastStatus, status.updatedAt >= transferCompletedAt else { return }

        if status.isIssueActive {
            failActiveSend(reason: "Printer needs attention: \(status.issueLabel)")
            return
        }

        if status.isProcessingPrint {
            sawPostTransferProcessing = true
            lastEvent = "printer processing (\(status.phaseLabel))"
            return
        }

        if status.isReadyForNextJob {
            completeActiveSend()
            return
        }

        if sawPostTransferProcessing {
            lastEvent = "waiting for ready (\(status.phaseLabel))"
        }
    }
}

extension HiPrintBLEClient: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            lastEvent = "bluetooth on"
            if case .connecting = connectionState { startScan() }
        case .unauthorized:
            failActiveSend(reason: "Bluetooth unauthorized")
            cleanup()
            connectionState = .failed(reason: "Bluetooth unauthorized")
            lastEvent = "bluetooth unauthorized"
        case .poweredOff:
            failActiveSend(reason: "Bluetooth powered off")
            cleanup()
            connectionState = .failed(reason: "Bluetooth powered off")
            lastEvent = "bluetooth off"
        case .unsupported:
            failActiveSend(reason: "Bluetooth unsupported")
            cleanup()
            connectionState = .failed(reason: "Bluetooth unsupported")
            lastEvent = "bluetooth unsupported"
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advName ?? ""

        let nameMatch = name.localizedCaseInsensitiveContains(targetNamePrefix)
        let knownMatch = preferredPeripheralID != nil && peripheral.identifier == preferredPeripheralID
        let advertisedServices = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let serviceMatch = advertisedServices.contains(HiPrintConstants.serviceUUID())

        let shouldConnect = knownMatch || nameMatch || (!isFallbackScan && serviceMatch)
        guard shouldConnect else { return }

        self.peripheral = peripheral
        self.deviceName = name.isEmpty ? nil : name
        central.stopScan()
        cleanupScanState()
        connectionState = .connecting
        lastEvent = "found \(name.isEmpty ? peripheral.identifier.uuidString : name)"
        central.connect(peripheral, options: nil)
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        preferredPeripheralID = peripheral.identifier
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: preferredPeripheralKey)

        connectionState = .connecting
        lastEvent = "connected, discovering services"
        peripheral.delegate = self
        peripheral.discoverServices([HiPrintConstants.serviceUUID()])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        failActiveSend(reason: "Failed to connect")
        connectionState = .failed(reason: error?.localizedDescription ?? "Failed to connect")
        lastEvent = "connect failed"
        cleanup()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        failActiveSend(reason: error?.localizedDescription ?? "Disconnected")
        cleanup()
        connectionState = .disconnected
        lastEvent = "disconnected"
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionState = .failed(reason: error.localizedDescription)
            lastEvent = "service discovery failed"
            central.cancelPeripheralConnection(peripheral)
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == HiPrintConstants.serviceUUID() }) else {
            connectionState = .failed(reason: "Printer service not found")
            lastEvent = "service missing"
            central.cancelPeripheralConnection(peripheral)
            return
        }

        lastEvent = "service discovered"
        peripheral.discoverCharacteristics([HiPrintConstants.writeUUID(), HiPrintConstants.readUUID()], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectionState = .failed(reason: error.localizedDescription)
            lastEvent = "characteristics failed"
            central.cancelPeripheralConnection(peripheral)
            return
        }

        var discoveredWrite: CBCharacteristic?
        var discoveredRead: CBCharacteristic?
        for c in service.characteristics ?? [] {
            if c.uuid == HiPrintConstants.writeUUID() { discoveredWrite = c }
            if c.uuid == HiPrintConstants.readUUID() { discoveredRead = c }
        }

        guard let discoveredWrite, let discoveredRead else {
            connectionState = .failed(reason: "Printer characteristics missing")
            lastEvent = "characteristics missing"
            central.cancelPeripheralConnection(peripheral)
            return
        }

        writeChar = discoveredWrite
        readChar = discoveredRead
        connectionState = .connected(name: deviceName)
        lastEvent = "characteristics ready"

        startStatusPolling()
        peripheral.readValue(for: discoveredRead)
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            lastEvent = "status read failed: \(error.localizedDescription)"
            return
        }
        if let data = characteristic.value {
            lastStatus = PrinterStatus(raw: data)
            lastEvent = "status updated"
            evaluateSendOutcomeFromStatus()
        }
    }

    public func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        guard isSending, let writeChar else { return }
        sendNext(peripheral: peripheral, writeChar: writeChar)
    }

    private func startStatusPolling() {
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let peripheral = self.peripheral, let readChar = self.readChar else { return }
            peripheral.readValue(for: readChar)
        }
    }

    private func sendNext(peripheral: CBPeripheral, writeChar: CBCharacteristic) {
        guard isSending else { return }

        if nextPacketIndex >= pendingPackets.count {
            markPacketTransferComplete()
            return
        }

        guard peripheral.canSendWriteWithoutResponse else { return }

        if paceMs <= 0 {
            while isSending && nextPacketIndex < pendingPackets.count && peripheral.canSendWriteWithoutResponse {
                let packet = pendingPackets[nextPacketIndex]
                peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
                nextPacketIndex += 1
                sendProgress = Double(nextPacketIndex) / Double(max(1, pendingPackets.count))
            }

            if nextPacketIndex >= pendingPackets.count {
                markPacketTransferComplete()
            }
            return
        }

        let packet = pendingPackets[nextPacketIndex]
        peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
        nextPacketIndex += 1
        sendProgress = Double(nextPacketIndex) / Double(max(1, pendingPackets.count))

        sendTimer?.invalidate()
        let interval = Double(paceMs) / 1000.0
        sendTimer = Timer.scheduledTimer(withTimeInterval: max(0.001, interval), repeats: false) { [weak self] _ in
            guard let self, let p = self.peripheral, let w = self.writeChar else { return }
            self.sendNext(peripheral: p, writeChar: w)
        }
    }
}

extension HiPrintBLEClient: @unchecked Sendable {}
