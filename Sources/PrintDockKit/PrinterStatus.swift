import Foundation

public struct PrinterStatus: Equatable {
    public let raw: Data
    public let updatedAt: Date

    public init(raw: Data, updatedAt: Date = Date()) {
        self.raw = raw
        self.updatedAt = updatedAt
    }

    public var rawHex: String {
        raw.map { String(format: "%02x", $0) }.joined()
    }

    public var phaseCode: UInt8? {
        byte(at: 2)
    }

    public var issueCode: UInt8? {
        byte(at: 3)
    }

    public var phaseCodeHex: String {
        guard let phaseCode else { return "n/a" }
        return String(format: "0x%02x", phaseCode)
    }

    public var issueCodeHex: String {
        guard let issueCode else { return "n/a" }
        return String(format: "0x%02x", issueCode)
    }

    public var phaseLabel: String {
        guard let phaseCode else { return "unknown" }
        switch phaseCode {
        case 0x00: return "preparing"
        case 0x01: return "layer 1"
        case 0x02: return "layer 2"
        case 0x03: return "layer 3"
        case 0x07: return "ready"
        case 0xFF: return "processing"
        default: return "phase \(phaseCodeHex)"
        }
    }

    public var issueLabel: String {
        guard let issueCode else { return "unknown" }
        if issueCode == 0 {
            return "none"
        }
        if issueCode == 0x09 {
            return "printer attention (0x09)"
        }
        return "issue \(issueCodeHex)"
    }

    public var isIssueActive: Bool {
        guard let issueCode else { return false }
        return issueCode != 0
    }

    public var isReadyForNextJob: Bool {
        phaseCode == 0x07 && !isIssueActive
    }

    public var isProcessingPrint: Bool {
        guard let phaseCode else { return false }
        switch phaseCode {
        case 0x00, 0x01, 0x02, 0x03, 0xFF:
            return true
        default:
            return false
        }
    }

    private func byte(at index: Int) -> UInt8? {
        guard raw.count > index else { return nil }
        return raw[index]
    }
}

public enum ConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected(name: String?)
    case disconnected
    case failed(reason: String)
}

public enum SendStartResult: Equatable {
    case started
    case rejected(reason: String)
}

public enum SendOutcome: Equatable {
    case completed
    case failed(reason: String)
}
