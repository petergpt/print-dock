import XCTest
import AppKit
@testable import PrintDockKit

final class ImagePipelineTests: XCTestCase {
    func testPipelineProducesCorrectSize() throws {
        let image = makeTestImage(size: CGSize(width: 1200, height: 800))
        let pipeline = ImagePipeline()
        let data = try pipeline.makePrintableJPEG(
            from: image,
            offset: .zero,
            zoom: 1.0,
            quality: 0.95
        )
        let nsImage = NSImage(data: data)
        XCTAssertNotNil(nsImage)

        let width = nsImage?.representations.first?.pixelsWide
        let height = nsImage?.representations.first?.pixelsHigh
        XCTAssertEqual(width, HiPrintConstants.imageWidth)
        XCTAssertEqual(height, HiPrintConstants.imageHeight)
    }

    private func makeTestImage(size: CGSize) -> NSImage {
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

        let img = NSImage(size: size)
        img.addRepresentation(rep)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        return img
    }
}
