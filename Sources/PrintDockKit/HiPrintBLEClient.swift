import Foundation
@preconcurrency import CoreBluetooth
import Combine

public final class HiPrintBLEClient: NSObject, ObservableObject {
    @Published public private(set) var connectionState: ConnectionState = .idle
    @Published public private(set) var lastStatus: PrinterStatus?
    @Published public private(set) var sendProgress: Double = 0
    @Published public private(set) var deviceName: String?
    @Published public private(set) var lastEvent: String = "idle"

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var readChar: CBCharacteristic?
    private var statusTimer: Timer?
    private var scanTimer: Timer?
    private var sendTimer: Timer?

    private var pendingPackets: [Data] = []
    private var nextPacketIndex = 0
    private var paceMs: Int = 2
    private var isSending = false

    private let targetNamePrefix: String

    public init(targetNamePrefix: String = "Hi-Print") {
        self.targetNamePrefix = targetNamePrefix
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

    public func connect() {
        lastEvent = "connect requested"
        if central.state == .poweredOn {
            startScan()
        } else {
            connectionState = .connecting
        }
    }

    public func disconnect() {
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        cleanup()
        connectionState = .disconnected
        lastEvent = "disconnected"
    }

    public func send(jpeg: Data, paceMs: Int = 2) {
        guard let peripheral, let writeChar else { return }
        self.paceMs = max(0, paceMs)
        let packets = HiPrintPacketizer.packetize(payload: jpeg)
        pendingPackets = packets
        nextPacketIndex = 0
        isSending = true
        sendProgress = 0
        sendNext(peripheral: peripheral, writeChar: writeChar)
    }

    private func startScan() {
        connectionState = .scanning
        lastEvent = "scan started"
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer?.invalidate()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.central.stopScan()
            if case .scanning = self.connectionState {
                self.connectionState = .failed(reason: "Scan timed out")
                self.lastEvent = "scan timeout"
            }
        }
    }

    private func cleanup() {
        statusTimer?.invalidate()
        statusTimer = nil
        scanTimer?.invalidate()
        scanTimer = nil
        sendTimer?.invalidate()
        sendTimer = nil
        writeChar = nil
        readChar = nil
        peripheral = nil
        pendingPackets = []
        nextPacketIndex = 0
        isSending = false
    }

}

extension HiPrintBLEClient: CBCentralManagerDelegate, CBPeripheralDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            lastEvent = "bluetooth on"
            if case .connecting = connectionState { startScan() }
        case .unauthorized:
            connectionState = .failed(reason: "Bluetooth unauthorized")
            lastEvent = "bluetooth unauthorized"
        case .poweredOff:
            connectionState = .failed(reason: "Bluetooth powered off")
            lastEvent = "bluetooth off"
        case .unsupported:
            connectionState = .failed(reason: "Bluetooth unsupported")
            lastEvent = "bluetooth unsupported"
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = peripheral.name ?? advName ?? ""
        if name.localizedCaseInsensitiveContains(targetNamePrefix) {
            self.peripheral = peripheral
            self.deviceName = name
            central.stopScan()
            scanTimer?.invalidate()
            connectionState = .connecting
            lastEvent = "found \(name)"
            central.connect(peripheral, options: nil)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionState = .connected(name: deviceName)
        lastEvent = "connected"
        peripheral.delegate = self
        peripheral.discoverServices([HiPrintConstants.serviceUUID()])
        startStatusPolling()
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        connectionState = .failed(reason: error?.localizedDescription ?? "Failed to connect")
        lastEvent = "connect failed"
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        cleanup()
        connectionState = .disconnected
        lastEvent = "disconnected"
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            connectionState = .failed(reason: error.localizedDescription)
            lastEvent = "service discovery failed"
            return
        }
        guard let services = peripheral.services else { return }
        for s in services where s.uuid == HiPrintConstants.serviceUUID() {
            lastEvent = "service discovered"
            peripheral.discoverCharacteristics([HiPrintConstants.writeUUID(), HiPrintConstants.readUUID()], for: s)
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            connectionState = .failed(reason: error.localizedDescription)
            lastEvent = "characteristics failed"
            return
        }
        for c in service.characteristics ?? [] {
            if c.uuid == HiPrintConstants.writeUUID() { writeChar = c }
            if c.uuid == HiPrintConstants.readUUID() { readChar = c }
        }
        if writeChar != nil && readChar != nil {
            lastEvent = "characteristics ready"
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value {
            lastStatus = PrinterStatus(raw: data)
            lastEvent = "status updated"
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
            isSending = false
            sendProgress = 1.0
            return
        }

        guard peripheral.canSendWriteWithoutResponse else { return }

        let packet = pendingPackets[nextPacketIndex]
        peripheral.writeValue(packet, for: writeChar, type: .withoutResponse)
        nextPacketIndex += 1
        sendProgress = Double(nextPacketIndex) / Double(max(1, pendingPackets.count))

        sendTimer?.invalidate()
        let interval = Double(paceMs) / 1000.0
        sendTimer = Timer.scheduledTimer(withTimeInterval: max(0.0, interval), repeats: false) { [weak self] _ in
            guard let self, let p = self.peripheral, let w = self.writeChar else { return }
            self.sendNext(peripheral: p, writeChar: w)
        }
    }
}

extension HiPrintBLEClient: @unchecked Sendable {}
