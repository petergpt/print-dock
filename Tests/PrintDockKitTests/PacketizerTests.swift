import XCTest
@testable import PrintDockKit

final class PacketizerTests: XCTestCase {
    func testHeaderEncodesLength() {
        let header = HiPrintPacketizer.makeHeader(payloadLength: 0x02A9B5)
        XCTAssertEqual(header.count, 10)
        XCTAssertEqual(Array(header[0..<3]), [0x02, 0xA9, 0xB5])
        XCTAssertEqual(Array(header[3..<10]), HiPrintConstants.headerTail)
    }

    func testPacketizationOffsets() {
        let payload = Data(repeating: 0xAB, count: 450)
        let packets = HiPrintPacketizer.packetize(payload: payload, maxDataBytes: 200)
        XCTAssertEqual(packets.count, 1 + 3)

        let first = packets[1]
        XCTAssertEqual(first[0], 0x00)
        XCTAssertEqual(first[1], 0x00)
        XCTAssertEqual(first[2], 0x00)
        XCTAssertEqual(first[3], 0x00)
        XCTAssertEqual(first[4], 0xC8)
        XCTAssertEqual(first.count, 205)

        let second = packets[2]
        XCTAssertEqual(second[0], 0x00)
        XCTAssertEqual(second[1], 0x00)
        XCTAssertEqual(second[2], 0xC8)

        let third = packets[3]
        XCTAssertEqual(third[0], 0x00)
        XCTAssertEqual(third[1], 0x01)
        XCTAssertEqual(third[2], 0x90)
        XCTAssertEqual(third[4], 0x32)
    }

    func testPacketizationRespectsCustomChunkSize() {
        let payload = Data(repeating: 0x11, count: 280)
        let packets = HiPrintPacketizer.packetize(payload: payload, maxDataBytes: 137)

        XCTAssertEqual(packets.count, 1 + 3)
        XCTAssertEqual(packets[1][4], 137)
        XCTAssertEqual(packets[2][4], 137)
        XCTAssertEqual(packets[3][4], 6)
        XCTAssertEqual(packets[3][2], 0x12) // offset low byte: 274
    }
}
