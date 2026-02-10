import XCTest
@testable import PrintDockKit

final class PrinterStatusTests: XCTestCase {
    func testReadyStatusDecoding() {
        let status = PrinterStatus(raw: data(hex: "02000700089800260315010105000000"))

        XCTAssertEqual(status.phaseCode, 0x07)
        XCTAssertEqual(status.issueCode, 0x00)
        XCTAssertEqual(status.phaseLabel, "ready")
        XCTAssertEqual(status.issueLabel, "none")
        XCTAssertTrue(status.isReadyForNextJob)
        XCTAssertFalse(status.isIssueActive)
        XCTAssertFalse(status.isProcessingPrint)
    }

    func testProcessingStatusDecoding() {
        let status = PrinterStatus(raw: data(hex: "0201ff00086600150315000105000000"))

        XCTAssertEqual(status.phaseCode, 0xFF)
        XCTAssertTrue(status.isProcessingPrint)
        XCTAssertFalse(status.isReadyForNextJob)
    }

    func testIssueStatusDecoding() {
        let status = PrinterStatus(raw: data(hex: "02000709089800280315000105000000"))

        XCTAssertEqual(status.phaseCode, 0x07)
        XCTAssertEqual(status.issueCode, 0x09)
        XCTAssertTrue(status.isIssueActive)
        XCTAssertFalse(status.isReadyForNextJob)
        XCTAssertEqual(status.issueLabel, "printer attention (0x09)")
    }

    private func data(hex: String) -> Data {
        var result = Data()
        result.reserveCapacity(hex.count / 2)

        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            let byte = UInt8(hex[index..<next], radix: 16)!
            result.append(byte)
            index = next
        }
        return result
    }
}
