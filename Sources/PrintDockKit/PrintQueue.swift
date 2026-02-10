import Foundation
import AppKit

public enum PrintJobState: String, Codable {
    case queued
    case sending
    case completed
    case failed
}

public struct PrintJob: Identifiable {
    public let id: UUID
    public let createdAt: Date
    public let image: NSImage
    public var state: PrintJobState
    public var progress: Double
    public var error: String?
    public var isFavorite: Bool
    public var placementOffset: CGSize
    public var zoom: Double

    public init(image: NSImage, placementOffset: CGSize, zoom: Double) {
        self.id = UUID()
        self.createdAt = Date()
        self.image = image
        self.state = .queued
        self.progress = 0
        self.error = nil
        self.isFavorite = false
        self.placementOffset = placementOffset
        self.zoom = zoom
    }
}

public final class PrintQueue: ObservableObject {
    @Published public private(set) var jobs: [PrintJob] = []
    private let maxHistoryJobs: Int

    public init(maxHistoryJobs: Int = 60) {
        self.maxHistoryJobs = max(0, maxHistoryJobs)
    }

    public func enqueue(_ image: NSImage, placementOffset: CGSize = .zero, zoom: Double = 1.0) -> UUID {
        let job = PrintJob(image: image, placementOffset: placementOffset, zoom: zoom)
        jobs.append(job)
        return job.id
    }

    public func update(
        _ id: UUID,
        state: PrintJobState,
        progress: Double? = nil,
        error: String? = nil,
        clearError: Bool = false
    ) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].state = state
        if let progress { jobs[idx].progress = progress }
        if clearError { jobs[idx].error = nil }
        if let error { jobs[idx].error = error }
        trimHistoryIfNeeded()
    }

    public func toggleFavorite(_ id: UUID) {
        guard let idx = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[idx].isFavorite.toggle()
        trimHistoryIfNeeded()
    }

    public func remove(_ id: UUID) {
        jobs.removeAll { $0.id == id }
    }

    public func clearCompleted() {
        jobs.removeAll { $0.state == .completed }
    }

    private func trimHistoryIfNeeded() {
        guard maxHistoryJobs >= 0 else { return }

        while terminalHistoryCount > maxHistoryJobs {
            guard let idx = jobs.firstIndex(where: { shouldTrim($0) }) else { return }
            jobs.remove(at: idx)
        }
    }

    private var terminalHistoryCount: Int {
        jobs.reduce(0) { partial, job in
            partial + (shouldTrim(job) ? 1 : 0)
        }
    }

    private func shouldTrim(_ job: PrintJob) -> Bool {
        !job.isFavorite && (job.state == .completed || job.state == .failed)
    }
}
