import XCTest
import Combine
import AppKit
import PrintDockKit
@testable import PrintDockApp

final class AppModelQueueTests: XCTestCase {
    func testRejectedSendMarksJobFailed() {
        let fakeClient = FakeHiPrintClient()
        fakeClient.nextSendResult = .rejected(reason: "Printer is not connected")

        let printer = PrinterController(client: fakeClient)
        let model = AppModel(printer: printer)
        model.selectedImage = makeImage(size: CGSize(width: 600, height: 900))

        model.printNow()

        XCTAssertEqual(model.queue.jobs.count, 1)
        XCTAssertEqual(model.queue.jobs[0].state, .failed)
        XCTAssertEqual(model.queue.jobs[0].error, "Printer is not connected")
    }

    func testFailedOutcomeMarksSendingJobFailed() {
        let fakeClient = FakeHiPrintClient()
        fakeClient.nextSendResult = .started

        let printer = PrinterController(client: fakeClient)
        let model = AppModel(printer: printer)
        model.selectedImage = makeImage(size: CGSize(width: 640, height: 1024))

        model.printNow()
        XCTAssertEqual(model.queue.jobs[0].state, .sending)

        fakeClient.sendOutcomeSubject.send(.failed(reason: "Disconnected"))
        pumpMainRunLoop(seconds: 0.15)

        XCTAssertEqual(model.queue.jobs[0].state, .failed)
        XCTAssertEqual(model.queue.jobs[0].error, "Disconnected")
    }

    func testCompletionStartsNextQueuedJob() {
        let fakeClient = FakeHiPrintClient()
        fakeClient.nextSendResult = .started

        let printer = PrinterController(client: fakeClient)
        let model = AppModel(printer: printer)

        model.selectedImage = makeImage(size: CGSize(width: 640, height: 1024))
        model.printNow()
        model.selectedImage = makeImage(size: CGSize(width: 700, height: 1000))
        model.printNow()

        XCTAssertEqual(model.queue.jobs.count, 2)
        XCTAssertEqual(model.queue.jobs[0].state, .sending)
        XCTAssertEqual(model.queue.jobs[1].state, .queued)
        XCTAssertEqual(fakeClient.sendCallCount, 1)

        fakeClient.sendOutcomeSubject.send(.completed)
        pumpMainRunLoop(seconds: 0.15)

        XCTAssertEqual(model.queue.jobs[0].state, .completed)
        XCTAssertEqual(model.queue.jobs[1].state, .sending)
        XCTAssertEqual(fakeClient.sendCallCount, 2)
    }

    func testCompletionIncrementsCelebrationCount() {
        let fakeClient = FakeHiPrintClient()
        fakeClient.nextSendResult = .started

        let printer = PrinterController(client: fakeClient)
        let model = AppModel(printer: printer)
        model.selectedImage = makeImage(size: CGSize(width: 640, height: 1024))

        model.printNow()
        XCTAssertEqual(model.celebrationCount, 0)

        fakeClient.sendOutcomeSubject.send(.completed)
        pumpMainRunLoop(seconds: 0.15)

        XCTAssertEqual(model.celebrationCount, 1)
    }

    func testProgressAtHundredPercentDoesNotCompleteWithoutOutcome() {
        let fakeClient = FakeHiPrintClient()
        fakeClient.nextSendResult = .started

        let printer = PrinterController(client: fakeClient)
        let model = AppModel(printer: printer)
        model.selectedImage = makeImage(size: CGSize(width: 640, height: 1024))

        model.printNow()
        XCTAssertEqual(model.queue.jobs[0].state, .sending)

        fakeClient.sendProgressSubject.send(1.0)
        pumpMainRunLoop(seconds: 0.15)

        XCTAssertEqual(model.queue.jobs[0].state, .sending)
        XCTAssertEqual(model.celebrationCount, 0)
    }

    private func makeImage(size: CGSize) -> NSImage {
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
        NSColor.systemBlue.setFill()
        NSBezierPath(rect: CGRect(x: 0, y: 0, width: size.width / 2, height: size.height)).fill()
        NSGraphicsContext.restoreGraphicsState()

        return image
    }

    private func pumpMainRunLoop(seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
    }
}

private final class FakeHiPrintClient: HiPrintClienting {
    let connectionStateSubject = CurrentValueSubject<ConnectionState, Never>(.connected(name: "Test"))
    let lastStatusSubject = CurrentValueSubject<PrinterStatus?, Never>(nil)
    let sendProgressSubject = CurrentValueSubject<Double, Never>(0)
    let sendOutcomeSubject = CurrentValueSubject<SendOutcome?, Never>(nil)
    let lastEventSubject = CurrentValueSubject<String, Never>("idle")

    var nextSendResult: SendStartResult = .started
    private(set) var sendCallCount = 0

    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> {
        connectionStateSubject.eraseToAnyPublisher()
    }

    var lastStatusPublisher: AnyPublisher<PrinterStatus?, Never> {
        lastStatusSubject.eraseToAnyPublisher()
    }

    var sendProgressPublisher: AnyPublisher<Double, Never> {
        sendProgressSubject.eraseToAnyPublisher()
    }

    var sendOutcomePublisher: AnyPublisher<SendOutcome?, Never> {
        sendOutcomeSubject.eraseToAnyPublisher()
    }

    var lastEventPublisher: AnyPublisher<String, Never> {
        lastEventSubject.eraseToAnyPublisher()
    }

    func connect() {}
    func disconnect() {}

    func send(jpeg: Data, paceMs: Int, timeout: TimeInterval) -> SendStartResult {
        sendCallCount += 1
        return nextSendResult
    }
}
