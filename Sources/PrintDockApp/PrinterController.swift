import Foundation
import Combine
import PrintDockKit

protocol HiPrintClienting: AnyObject {
    var connectionStatePublisher: AnyPublisher<ConnectionState, Never> { get }
    var lastStatusPublisher: AnyPublisher<PrinterStatus?, Never> { get }
    var sendProgressPublisher: AnyPublisher<Double, Never> { get }
    var sendOutcomePublisher: AnyPublisher<SendOutcome?, Never> { get }
    var lastEventPublisher: AnyPublisher<String, Never> { get }

    func connect()
    func disconnect()
    func send(jpeg: Data, paceMs: Int, timeout: TimeInterval) -> SendStartResult
}

extension HiPrintBLEClient: HiPrintClienting {}

final class PrinterController: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var lastStatus: PrinterStatus?
    @Published private(set) var sendProgress: Double = 0
    @Published private(set) var sendOutcome: SendOutcome?
    @Published private(set) var lastEvent: String = ""

    private let client: any HiPrintClienting
    private var cancellables: Set<AnyCancellable> = []

    init(client: any HiPrintClienting = HiPrintBLEClient()) {
        self.client = client
        bind()
    }

    private func bind() {
        cancellables.removeAll()
        client.connectionStatePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.connectionState = $0 }
            .store(in: &cancellables)
        client.lastStatusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastStatus = $0 }
            .store(in: &cancellables)
        client.sendProgressPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sendProgress = $0 }
            .store(in: &cancellables)
        client.sendOutcomePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.sendOutcome = $0 }
            .store(in: &cancellables)
        client.lastEventPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastEvent = $0 }
            .store(in: &cancellables)
    }

    func connect() { client.connect() }
    func disconnect() { client.disconnect() }
    func send(jpeg: Data, paceMs: Int, timeout: TimeInterval) -> SendStartResult {
        client.send(jpeg: jpeg, paceMs: paceMs, timeout: timeout)
    }
}
