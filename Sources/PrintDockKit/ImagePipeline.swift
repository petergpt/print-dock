import Foundation
import AppKit
import CoreImage
import CoreGraphics
import UniformTypeIdentifiers

public struct ImagePipeline {
    public init() {}

    public func makePrintableJPEG(
        from image: NSImage,
        offset: CGSize = .zero,
        zoom: Double = 1.0,
        quality: Double = 0.95
    ) throws -> Data {
        guard let cgImage = image.cgImageForCurrentRep() else {
            throw NSError(domain: "PrintDock", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid image"]) 
        }

        let targetSize = CGSize(width: HiPrintConstants.imageWidth, height: HiPrintConstants.imageHeight)
        let rendered = renderToTarget(cgImage, targetSize: targetSize, offset: offset, zoom: zoom)

        guard let jpg = encodeJPEG(cgImage: rendered, quality: quality) else {
            throw NSError(domain: "PrintDock", code: 2, userInfo: [NSLocalizedDescriptionKey: "JPEG encode failed"]) 
        }
        return jpg
    }

    private func renderToTarget(_ image: CGImage, targetSize: CGSize, offset: CGSize, zoom: Double) -> CGImage {
        let width = targetSize.width
        let height = targetSize.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            return image
        }

        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let srcSize = CGSize(width: image.width, height: image.height)
        let scaleX = width / srcSize.width
        let scaleY = height / srcSize.height
        let baseScale = max(scaleX, scaleY)
        let scale = max(1.0, zoom) * baseScale
        let drawSize = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
        let centerOrigin = CGPoint(x: (width - drawSize.width) / 2, y: (height - drawSize.height) / 2)

        let maxOffsetX = max(0, (drawSize.width - width) / 2)
        let maxOffsetY = max(0, (drawSize.height - height) / 2)
        let clampedOffset = CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )

        let drawOrigin = CGPoint(x: centerOrigin.x + clampedOffset.width, y: centerOrigin.y + clampedOffset.height)
        let drawRect = CGRect(origin: drawOrigin, size: drawSize)

        ctx.interpolationQuality = .high
        ctx.draw(image, in: drawRect)
        return ctx.makeImage() ?? image
    }

    private func encodeJPEG(cgImage: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(dest, cgImage, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}

public extension NSImage {
    func cgImageForCurrentRep() -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
