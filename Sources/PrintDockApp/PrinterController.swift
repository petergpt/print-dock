import Foundation
import Combine
import PrintDockKit

final class PrinterController: ObservableObject {
    @Published private(set) var connectionState: ConnectionState = .idle
    @Published private(set) var lastStatus: PrinterStatus?
    @Published private(set) var sendProgress: Double = 0
    @Published private(set) var lastEvent: String = ""

    private let client: HiPrintBLEClient
    private var cancellables: Set<AnyCancellable> = []

    init() {
        self.client = HiPrintBLEClient()
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
        client.$lastEvent
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.lastEvent = $0 }
            .store(in: &cancellables)
    }

    func connect() { client.connect() }
    func disconnect() { client.disconnect() }
    func send(jpeg: Data, paceMs: Int) { client.send(jpeg: jpeg, paceMs: paceMs) }
}
