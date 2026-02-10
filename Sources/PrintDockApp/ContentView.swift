import SwiftUI
import UniformTypeIdentifiers
import AppKit
import PrintDockKit

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
            Divider()
            CanvasView()
        }
        .background(Theme.background)
        .tint(Theme.accent)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if model.printer.sendProgress > 0 && model.printer.sendProgress < 1 {
                    PrintProgressIndicator(progress: model.printer.sendProgress)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { model.printNow() }) {
                    Label("Print", systemImage: "printer.fill")
                }
                .accessibilityIdentifier("print_button")
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(!canPrint)

                Button(action: { model.clearSelection() }) {
                    Image(systemName: "trash")
                }
                .help("Clear canvas")
                .disabled(model.selectedImage == nil)
            }
        }
        .alert("Print error", isPresented: Binding(
            get: { model.lastError != nil },
            set: { _ in model.clearError() }
        )) {
            Button("OK", role: .cancel) { model.clearError() }
        } message: {
            Text(model.lastError ?? "Unknown error")
        }
    }

    private var canPrint: Bool {
        guard model.selectedImage != nil else { return false }
        if case .connected = model.printer.connectionState { return true }
        return false
    }
}

struct PrintProgressIndicator: View {
    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            Text("Printing")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
            PrintPassBar(progress: progress)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .cornerRadius(12)
    }
}

struct PrintPassBar: View {
    let progress: Double
    private let colors: [Color] = [
        Color(red: 1.0, green: 0.86, blue: 0.20),   // yellow
        Color(red: 0.98, green: 0.35, blue: 0.45),  // magenta/red
        Color(red: 0.22, green: 0.78, blue: 0.82)   // cyan/green
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { idx in
                PassSegment(progress: segmentProgress(idx), color: colors[idx])
            }
        }
    }

    private func segmentProgress(_ idx: Int) -> Double {
        let scaled = progress * 3.0 - Double(idx)
        return min(max(scaled, 0), 1)
    }
}

struct PassSegment: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(Theme.border.opacity(0.5))
            GeometryReader { geo in
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(progress))
            }
        }
        .frame(width: 28, height: 6)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            DeviceCardView()
            PileListView()
            Spacer()
        }
        .padding(16)
        .frame(minWidth: 240, idealWidth: 260, maxWidth: 280)
        .background(Theme.background)
    }
}

struct DeviceCardView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Printer")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                Spacer()
                StatusPill(state: model.printer.connectionState)
            }

            Text(deviceName)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.ink)

            Text(statusLine)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)

            if !model.printer.lastEvent.isEmpty {
                Text("BLE: \(model.printer.lastEvent)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button(action: { model.connect() }) {
                    Label("Connect", systemImage: "bolt.horizontal.fill")
                }
                .accessibilityIdentifier("connect_button")
                .buttonStyle(.bordered)
                .disabled(isConnected || isConnecting)

                Button(action: { model.disconnect() }) {
                    Label("Disconnect", systemImage: "xmark.circle.fill")
                }
                .buttonStyle(.bordered)
                .disabled(!isConnected && !isConnecting)
            }
        }
        .padding(12)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 6, x: 0, y: 2)
        .cornerRadius(12)
    }

    private var deviceName: String {
        switch model.printer.connectionState {
        case .connected(let name):
            return name ?? "Hi-Print 2×3"
        case .connecting:
            return "Connecting…"
        case .scanning:
            return "Scanning…"
        case .failed(let reason):
            return "Failed: \(reason)"
        default:
            return "Not connected"
        }
    }

    private var statusLine: String {
        switch model.printer.connectionState {
        case .connected:
            guard let status = model.printer.lastStatus else {
                return "Connected"
            }
            if status.isIssueActive {
                return "Attention needed: \(status.issueLabel)"
            }
            if status.isReadyForNextJob {
                return "Ready to print"
            }
            return "Printer \(status.phaseLabel)"
        case .connecting: return "Pairing"
        case .scanning: return "Searching"
        case .failed: return "Connection issue"
        case .disconnected: return "Offline"
        default: return "Idle"
        }
    }

    private var isConnected: Bool {
        if case .connected = model.printer.connectionState { return true }
        return false
    }

    private var isConnecting: Bool {
        if case .connecting = model.printer.connectionState { return true }
        if case .scanning = model.printer.connectionState { return true }
        return false
    }
}

struct PileListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Pile")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                Spacer()
                Button("Clear Printed") { model.queue.clearCompleted() }
                    .font(.system(size: 11))
                    .disabled(printedJobs.isEmpty)
            }

            if model.queue.jobs.isEmpty {
                Text("No photos yet")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !favoriteJobs.isEmpty {
                            SectionHeaderView(title: "Favorites")
                            ForEach(favoriteJobs) { job in
                                JobRowView(job: job)
                            }
                        }

                        if !readyJobs.isEmpty {
                            SectionHeaderView(title: "Ready")
                            ForEach(readyJobs) { job in
                                JobRowView(job: job)
                            }
                        }

                        if !printingJobs.isEmpty {
                            SectionHeaderView(title: "Printing")
                            ForEach(printingJobs) { job in
                                JobRowView(job: job)
                            }
                        }

                        if !failedJobs.isEmpty {
                            SectionHeaderView(title: "Needs Attention")
                            ForEach(failedJobs) { job in
                                JobRowView(job: job)
                            }
                        }

                        if !printedJobs.isEmpty {
                            SectionHeaderView(title: "Printed")
                            ForEach(printedJobs) { job in
                                JobRowView(job: job)
                            }
                        }
                    }
                }
                .frame(minHeight: 160)
            }
        }
        .padding(12)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .shadow(color: Theme.shadow, radius: 6, x: 0, y: 2)
        .cornerRadius(12)
    }

    private var favoriteJobs: [PrintJob] {
        model.queue.jobs.filter { $0.isFavorite }
    }

    private var readyJobs: [PrintJob] {
        model.queue.jobs.filter { $0.state == .queued && !$0.isFavorite }
    }

    private var printingJobs: [PrintJob] {
        model.queue.jobs.filter { $0.state == .sending && !$0.isFavorite }
    }

    private var failedJobs: [PrintJob] {
        model.queue.jobs.filter { $0.state == .failed && !$0.isFavorite }
    }

    private var printedJobs: [PrintJob] {
        model.queue.jobs.filter { $0.state == .completed && !$0.isFavorite }
    }
}

struct SectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Theme.muted)
            .padding(.top, 4)
    }
}

struct JobRowView: View {
    @EnvironmentObject private var model: AppModel
    let job: PrintJob

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: job.image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 42, height: 42)
                .clipped()
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(jobTitle)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.ink)

                if job.state == .sending {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                } else {
                    Text(statusLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer()

            Button(action: { model.queue.toggleFavorite(job.id) }) {
                Image(systemName: job.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(job.isFavorite ? Theme.accent : Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(rowBackground)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(rowBorder, lineWidth: 1))
        .cornerRadius(10)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selectJob(job)
        }
    }

    private var statusLabel: String {
        switch job.state {
        case .queued: return "Ready"
        case .sending: return "Printing"
        case .completed: return "Printed"
        case .failed: return "Failed"
        }
    }

    private var jobTitle: String {
        job.isFavorite ? "Favorite" : "Photo"
    }

    private var rowBackground: Color {
        model.selectedJobID == job.id ? Theme.accent.opacity(0.15) : Theme.card
    }

    private var rowBorder: Color {
        model.selectedJobID == job.id ? Theme.accent.opacity(0.4) : Theme.border
    }
}

struct CanvasView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isTargeted = false
    @State private var showImporter = false
    @State private var isHovering = false
    @State private var dragStart: CGSize? = nil
    @State private var showCelebration = false
    @State private var celebrationTrigger = 0
    @State private var canvasGlow = false

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let frameSize = fitFrame(in: containerSize)

            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(Theme.card)
                    .shadow(color: Theme.shadow, radius: 18, x: 0, y: 8)

                ZStack {
                    if let image = model.selectedImage {
                        let drawSize = model.previewDrawSize(in: frameSize)
                        let offset = model.previewOffset(in: frameSize)

                        Image(nsImage: image)
                            .resizable()
                            .frame(width: drawSize.width, height: drawSize.height)
                            .position(x: frameSize.width / 2 + offset.width,
                                      y: frameSize.height / 2 + offset.height)
                            .clipped()
                            .allowsHitTesting(false)

                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .gesture(dragGesture(frameSize: frameSize))
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 36))
                                .foregroundStyle(Theme.muted)
                            Text("Drag & drop a photo")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.muted)
                            Button("Choose Photo") {
                                showImporter = true
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("choose_photo_button")
                        }
                    }
                }
                .frame(width: frameSize.width, height: frameSize.height)
                .background(Theme.canvas)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(isTargeted ? Theme.accent : Theme.border, lineWidth: isTargeted ? 2 : 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Theme.accent.opacity(canvasGlow ? 0.55 : 0), lineWidth: canvasGlow ? 4 : 1)
                )
                .overlay {
                    if showCelebration {
                        CelebrationBurstView(trigger: celebrationTrigger)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if model.selectedImage != nil {
                        Button("Replace") { showImporter = true }
                            .buttonStyle(.bordered)
                            .padding(12)
                            .opacity(isHovering ? 1 : 0)
                    }
                }
                .overlay(alignment: .bottom) {
                    if model.selectedImage != nil {
                        Text("Drag to position")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.muted)
                            .padding(.bottom, 10)
                    }
                }
                .onHover { hovering in
                    isHovering = hovering
                }
                .overlay(alignment: .bottomTrailing) {
                    if model.selectedImage != nil {
                        ZoomControlView()
                            .padding(12)
                    }
                }
            }
            .frame(width: containerSize.width, height: containerSize.height)
            .padding(18)
            .onTapGesture {
                if model.selectedImage == nil {
                    showImporter = true
                }
            }
            .onChange(of: model.celebrationCount) { _ in
                triggerCelebration()
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        DispatchQueue.main.async {
                            model.loadImage(from: url)
                        }
                    }
                }
                return true
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url):
                    model.loadImage(from: url)
                case .failure:
                    break
                }
            }
            .accessibilityIdentifier("canvas")
        }
    }

    private func dragGesture(frameSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStart == nil {
                    dragStart = model.placement.offset
                }
                if let start = dragStart {
                    model.updatePlacement(startOffset: start, translation: value.translation, in: frameSize)
                }
            }
            .onEnded { _ in
                dragStart = nil
            }
    }

    private func fitFrame(in container: CGSize) -> CGSize {
        let inset: CGFloat = 36
        let available = CGSize(width: max(0, container.width - inset * 2), height: max(0, container.height - inset * 2))
        let ratio = CGFloat(HiPrintConstants.imageWidth) / CGFloat(HiPrintConstants.imageHeight)
        let width = min(available.width, available.height * ratio)
        let height = width / ratio
        return CGSize(width: width, height: height)
    }

    private func triggerCelebration() {
        guard model.celebrationCount > 0 else { return }
        celebrationTrigger += 1
        showCelebration = true
        withAnimation(.easeOut(duration: 0.3)) {
            canvasGlow = true
        }

        if let sound = NSSound(named: NSSound.Name("Glass")) {
            sound.play()
        } else {
            NSSound.beep()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(.easeOut(duration: 0.25)) {
                canvasGlow = false
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation(.easeOut(duration: 0.25)) {
                showCelebration = false
            }
        }
    }
}

struct CelebrationBurstView: View {
    let trigger: Int

    private enum Corner: Int, CaseIterable {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight

        var direction: CGSize {
            switch self {
            case .topLeft: return CGSize(width: 1, height: 1)
            case .topRight: return CGSize(width: -1, height: 1)
            case .bottomLeft: return CGSize(width: 1, height: -1)
            case .bottomRight: return CGSize(width: -1, height: -1)
            }
        }
    }

    private let colors: [Color] = [
        Color(red: 1.0, green: 0.86, blue: 0.20),
        Color(red: 0.98, green: 0.35, blue: 0.45),
        Color(red: 0.22, green: 0.78, blue: 0.82),
        Color(red: 1.0, green: 0.62, blue: 0.18)
    ]

    @State private var exploded = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(Corner.allCases, id: \.rawValue) { corner in
                    ForEach(0..<10, id: \.self) { idx in
                        Capsule()
                            .fill(colors[(idx + corner.rawValue) % colors.count])
                            .frame(width: CGFloat(4 + (idx % 3)), height: CGFloat(10 + (idx % 5)))
                            .position(startPosition(for: corner, in: proxy.size))
                            .offset(exploded ? burstOffset(for: corner, index: idx) : .zero)
                            .rotationEffect(.degrees(exploded ? Double(idx * 31) : 0))
                            .opacity(exploded ? 0 : 0.95)
                    }
                }
            }
            .onAppear { restart() }
            .onChange(of: trigger) { _ in restart() }
        }
    }

    private func startPosition(for corner: Corner, in size: CGSize) -> CGPoint {
        let inset: CGFloat = 20
        switch corner {
        case .topLeft:
            return CGPoint(x: inset, y: inset)
        case .topRight:
            return CGPoint(x: size.width - inset, y: inset)
        case .bottomLeft:
            return CGPoint(x: inset, y: size.height - inset)
        case .bottomRight:
            return CGPoint(x: size.width - inset, y: size.height - inset)
        }
    }

    private func burstOffset(for corner: Corner, index: Int) -> CGSize {
        let direction = corner.direction
        let distance = CGFloat(28 + ((index * 13) % 48))
        let lateral = CGFloat((index % 5) - 2) * 8

        let x = direction.width * distance - direction.height * lateral
        let y = direction.height * distance + direction.width * lateral
        return CGSize(width: x, height: y)
    }

    private func restart() {
        exploded = false
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.9)) {
                exploded = true
            }
        }
    }
}

struct ZoomControlView: View {
    @EnvironmentObject private var model: AppModel
    private let minZoom: Double = 1.0
    private let maxZoom: Double = 2.5

    var body: some View {
        HStack(spacing: 8) {
            Button(action: { setZoom(model.placement.zoom - 0.1) }) {
                Image(systemName: "minus")
            }
            .buttonStyle(.borderless)

            Slider(value: Binding(
                get: { model.placement.zoom },
                set: { model.setZoom($0) }
            ), in: minZoom...maxZoom)
            .frame(width: 120)

            Button(action: { setZoom(model.placement.zoom + 0.1) }) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)

            Button(action: { model.recenter() }) {
                Image(systemName: "viewfinder")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(Theme.panel)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
        .cornerRadius(12)
    }

    private func setZoom(_ value: Double) {
        let clamped = min(maxZoom, max(minZoom, value))
        model.setZoom(clamped)
    }
}

struct StatusPill: View {
    let state: ConnectionState

    var body: some View {
        Text(label)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .cornerRadius(10)
    }

    private var label: String {
        switch state {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .scanning: return "Scanning"
        case .failed: return "Error"
        case .disconnected: return "Offline"
        default: return "Idle"
        }
    }

    private var color: Color {
        switch state {
        case .connected: return .green
        case .connecting, .scanning: return .orange
        case .failed: return .red
        case .disconnected: return .gray
        default: return .gray
        }
    }
}
