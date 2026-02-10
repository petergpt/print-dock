import Foundation
import AppKit
import Combine
import CoreImage
import ImageIO
import PrintDockKit

final class AppModel: ObservableObject {
    @Published var selectedImage: NSImage?
    @Published var placement = Placement()
    @Published var selectedJobID: UUID?
    @Published var lastError: String?
    @Published private(set) var celebrationCount: Int = 0

    let printer: PrinterController
    let queue: PrintQueue
    private let pipeline: ImagePipeline
    private let ciContext = CIContext(options: nil)
    private let paceMs: Int
    private let jpegQuality: Double
    private let sendTimeout: TimeInterval

    private var cancellables: Set<AnyCancellable> = []
    private var pendingJobs: [UUID] = []
    private var payloads: [UUID: Data] = [:]
    private var currentJob: UUID?

    init(
        printer: PrinterController = PrinterController(),
        queue: PrintQueue = PrintQueue(),
        pipeline: ImagePipeline = ImagePipeline(),
        paceMs: Int = 12,
        jpegQuality: Double = 0.98,
        sendTimeout: TimeInterval = 90
    ) {
        self.printer = printer
        self.queue = queue
        self.pipeline = pipeline
        self.paceMs = paceMs
        self.jpegQuality = jpegQuality
        self.sendTimeout = sendTimeout

        printer.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        queue.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        printer.$sendProgress
            .sink { [weak self] progress in
                self?.handleProgress(progress)
            }
            .store(in: &cancellables)

        printer.$sendOutcome
            .compactMap { $0 }
            .sink { [weak self] outcome in
                self?.handleSendOutcome(outcome)
            }
            .store(in: &cancellables)
    }

    func loadImage(from url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer {
            if needsAccess { url.stopAccessingSecurityScopedResource() }
        }
        if let image = loadAndNormalizeImage(url: url) {
            selectedImage = image
            selectedJobID = nil
            resetPlacement()
        }
    }

    func printNow() {
        guard let image = selectedImage else { return }
        do {
            let outputOffset = offsetForPrint(image: image)
            let data = try pipeline.makePrintableJPEG(
                from: image,
                offset: outputOffset,
                zoom: placement.zoom,
                quality: jpegQuality
            )

            let id = queue.enqueue(image, placementOffset: placement.offset, zoom: placement.zoom)
            payloads[id] = data
            pendingJobs.append(id)

            sendNextIfNeeded()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func clearError() { lastError = nil }

    func connect() { printer.connect() }
    func disconnect() { printer.disconnect() }

    func clearSelection() {
        selectedImage = nil
        selectedJobID = nil
    }

    func selectJob(_ job: PrintJob) {
        selectedJobID = job.id
        selectedImage = job.image
        placement = Placement(offset: job.placementOffset, zoom: job.zoom)
    }

    func resetPlacement() {
        placement = Placement()
    }

    func previewDrawSize(in frameSize: CGSize) -> CGSize {
        guard let image = selectedImage else { return .zero }
        return drawSize(for: image, targetSize: frameSize, zoom: placement.zoom)
    }

    func previewOffset(in frameSize: CGSize) -> CGSize {
        guard let image = selectedImage else { return .zero }
        let maxOffset = maxOffset(for: image, targetSize: frameSize, zoom: placement.zoom)
        return CGSize(
            width: placement.offset.width * maxOffset.width,
            height: placement.offset.height * maxOffset.height
        )
    }

    func updatePlacement(startOffset: CGSize, translation: CGSize, in frameSize: CGSize) {
        guard let image = selectedImage else { return }
        let maxOffset = maxOffset(for: image, targetSize: frameSize, zoom: placement.zoom)
        let dx = maxOffset.width > 0 ? translation.width / maxOffset.width : 0
        let dy = maxOffset.height > 0 ? translation.height / maxOffset.height : 0
        var next = placement
        next.offset = CGSize(
            width: clamp(startOffset.width + dx),
            height: clamp(startOffset.height + dy)
        )
        placement = next
    }

    func setZoom(_ value: Double) {
        var next = placement
        next.zoom = max(1.0, value)
        placement = next
    }

    func recenter() {
        var next = placement
        next.offset = .zero
        placement = next
    }

    private func sendNextIfNeeded() {
        guard currentJob == nil else { return }

        while !pendingJobs.isEmpty {
            let id = pendingJobs.removeFirst()
            guard let payload = payloads[id] else {
                queue.update(id, state: .failed, progress: 0, error: "Missing print payload")
                continue
            }

            currentJob = id
            queue.update(id, state: .sending, progress: 0, clearError: true)
            let result = printer.send(jpeg: payload, paceMs: paceMs, timeout: sendTimeout)
            switch result {
            case .started:
                return
            case .rejected(let reason):
                queue.update(id, state: .failed, progress: 0, error: reason)
                payloads.removeValue(forKey: id)
                currentJob = nil
                lastError = reason
            }
        }
    }

    private func handleProgress(_ progress: Double) {
        guard let id = currentJob else { return }
        queue.update(id, state: .sending, progress: progress)
    }

    private func handleSendOutcome(_ outcome: SendOutcome) {
        guard let id = currentJob else { return }

        switch outcome {
        case .completed:
            queue.update(id, state: .completed, progress: 1.0)
            celebrationCount += 1
        case .failed(let reason):
            queue.update(id, state: .failed, progress: 0, error: reason)
            lastError = reason
        }

        payloads.removeValue(forKey: id)
        currentJob = nil
        sendNextIfNeeded()
    }

    private func offsetForPrint(image: NSImage) -> CGSize {
        let target = CGSize(width: HiPrintConstants.imageWidth, height: HiPrintConstants.imageHeight)
        let maxOffset = maxOffset(for: image, targetSize: target, zoom: placement.zoom)
        return CGSize(
            width: placement.offset.width * maxOffset.width,
            height: -placement.offset.height * maxOffset.height
        )
    }

    private func maxOffset(for image: NSImage, targetSize: CGSize, zoom: Double) -> CGSize {
        let srcSize = imagePixelSize(image)
        let scaleX = targetSize.width / srcSize.width
        let scaleY = targetSize.height / srcSize.height
        let baseScale = max(scaleX, scaleY)
        let scale = max(1.0, zoom) * baseScale
        let drawSize = CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
        return CGSize(
            width: max(0, (drawSize.width - targetSize.width) / 2),
            height: max(0, (drawSize.height - targetSize.height) / 2)
        )
    }

    private func drawSize(for image: NSImage, targetSize: CGSize, zoom: Double) -> CGSize {
        let srcSize = imagePixelSize(image)
        let scaleX = targetSize.width / srcSize.width
        let scaleY = targetSize.height / srcSize.height
        let baseScale = max(scaleX, scaleY)
        let scale = max(1.0, zoom) * baseScale
        return CGSize(width: srcSize.width * scale, height: srcSize.height * scale)
    }

    private func imagePixelSize(_ image: NSImage) -> CGSize {
        if let cg = image.cgImageForCurrentRep() {
            return CGSize(width: cg.width, height: cg.height)
        }
        return image.size
    }

    private func clamp(_ value: CGFloat) -> CGFloat {
        min(max(value, -1), 1)
    }

    private func loadAndNormalizeImage(url: URL) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return nil
        }

        let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1

        var ciImage = CIImage(cgImage: cgImage).oriented(forExifOrientation: Int32(orientation))
        var extent = ciImage.extent

        // Auto-rotate landscape images to portrait
        if extent.width > extent.height {
            ciImage = ciImage.oriented(.right)
            extent = ciImage.extent
        }

        guard let finalCG = ciContext.createCGImage(ciImage, from: extent) else {
            return NSImage(cgImage: cgImage, size: .zero)
        }

        return NSImage(cgImage: finalCG, size: NSSize(width: extent.width, height: extent.height))
    }
}

struct Placement {
    var offset: CGSize = .zero
    var zoom: Double = 1.0
}
