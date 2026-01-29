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
}

public enum ConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected(name: String?)
    case disconnected
    case failed(reason: String)
}
