import XCTest
import AppKit
@testable import PrintDockKit

final class PrintQueueTests: XCTestCase {
    func testUpdateCanClearError() {
        let queue = PrintQueue()
        let id = queue.enqueue(makeImage())

        queue.update(id, state: .failed, error: "Disconnected")
        XCTAssertEqual(queue.jobs.first?.error, "Disconnected")

        queue.update(id, state: .sending, progress: 0, clearError: true)
        XCTAssertNil(queue.jobs.first?.error)
    }

    func testHistoryTrimDropsOldestTerminalNonFavoriteJobs() {
        let queue = PrintQueue(maxHistoryJobs: 2)

        let id1 = queue.enqueue(makeImage())
        let id2 = queue.enqueue(makeImage())
        let id3 = queue.enqueue(makeImage())

        queue.update(id1, state: .completed, progress: 1)
        queue.update(id2, state: .completed, progress: 1)
        queue.update(id3, state: .completed, progress: 1)

        let ids = queue.jobs.map(\.id)
        XCTAssertEqual(ids, [id2, id3])
    }

    func testHistoryTrimPreservesFavoriteTerminalJobs() {
        let queue = PrintQueue(maxHistoryJobs: 1)

        let favorite = queue.enqueue(makeImage())
        let regular = queue.enqueue(makeImage())

        queue.toggleFavorite(favorite)
        queue.update(favorite, state: .completed, progress: 1)
        queue.update(regular, state: .completed, progress: 1)

        XCTAssertEqual(queue.jobs.count, 2)
        XCTAssertTrue(queue.jobs.contains(where: { $0.id == favorite && $0.isFavorite }))
        XCTAssertTrue(queue.jobs.contains(where: { $0.id == regular }))
    }

    private func makeImage() -> NSImage {
        let size = CGSize(width: 640, height: 1024)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!

        let image = NSImage(size: size)
        image.addRepresentation(rep)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSColor.systemPink.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        return image
    }
}
