import Foundation
import CoreBluetooth

public enum HiPrintConstants {
    public static let serviceUUIDString = "C3D1E0CB-9C4E-434E-A915-12097CD84F81"
    public static let writeUUIDString = "C3D1E0CC-9C4E-434E-A915-12097CD84F81"
    public static let readUUIDString = "C3D1E0CD-9C4E-434E-A915-12097CD84F81"

    public static func serviceUUID() -> CBUUID { CBUUID(string: serviceUUIDString) }
    public static func writeUUID() -> CBUUID { CBUUID(string: writeUUIDString) }
    public static func readUUID() -> CBUUID { CBUUID(string: readUUIDString) }

    public static let imageWidth: Int = 640
    public static let imageHeight: Int = 1024

    // Observed header after 3-byte length.
    public static let headerTail: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00]
}
