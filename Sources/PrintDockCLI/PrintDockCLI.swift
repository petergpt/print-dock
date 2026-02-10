import Foundation
import AppKit
import PrintDockKit

struct CLIOptions {
    var namePrefix: String = "Hi-Print"
    var timeout: TimeInterval = 12
    var paceMs: Int = 12
}

enum Command {
    case scan
    case status
    case print(path: String)
    case help
}

@main
struct PrintDockCLI {
    static func main() {
        run()
    }
}

func run() {
    let args = CommandLine.arguments.dropFirst()
    let (command, options) = parseArguments(args)

    switch command {
    case .help:
        printUsage()
        exit(0)
    case .scan:
        runScan(options: options)
    case .status:
        runStatus(options: options)
    case .print(let path):
        runPrint(path: path, options: options)
    }
}

func parseArguments(_ args: ArraySlice<String>) -> (Command, CLIOptions) {
    var opts = CLIOptions()
    var remaining: [String] = []
    var iterator = args.makeIterator()

    while let arg = iterator.next() {
        switch arg {
        case "--prefix":
            if let value = iterator.next() { opts.namePrefix = value }
        case "--timeout":
            if let value = iterator.next(), let t = TimeInterval(value) { opts.timeout = t }
        case "--pace":
            if let value = iterator.next(), let pace = Int(value) { opts.paceMs = pace }
        case "-h", "--help":
            return (.help, opts)
        default:
            remaining.append(arg)
        }
    }

    guard let first = remaining.first else {
        return (.help, opts)
    }

    switch first {
    case "scan":
        return (.scan, opts)
    case "status":
        return (.status, opts)
    case "print":
        if remaining.count >= 2 {
            return (.print(path: remaining[1]), opts)
        }
        return (.help, opts)
    default:
        return (.help, opts)
    }
}

func printUsage() {
    let usage = """
    printdock — Print Dock connectivity CLI

    Usage:
      printdock scan [--prefix "Hi-Print"] [--timeout 12]
      printdock status [--prefix "Hi-Print"] [--timeout 12]
      printdock print <imagePath> [--prefix "Hi-Print"] [--timeout 30] [--pace 12]

    Options:
      --prefix   Device name prefix to match (default: Hi-Print)
      --timeout  Seconds to wait for connect/finish (default: 12)
      --pace     Milliseconds between BLE packets when printing (default: 12)
    """
    print(usage)
}

func runScan(options: CLIOptions) {
    let client = HiPrintBLEClient(targetNamePrefix: options.namePrefix)
    client.connect()
    let connected = waitForConnection(client, timeout: options.timeout)
    if connected {
        print("FOUND \(client.deviceName ?? "device")")
        client.disconnect()
        exit(0)
    }
    printError("No device found (prefix: \(options.namePrefix)).")
    exit(1)
}

func runStatus(options: CLIOptions) {
    let client = HiPrintBLEClient(targetNamePrefix: options.namePrefix)
    client.connect()
    guard waitForConnection(client, timeout: options.timeout) else {
        printError("Failed to connect.")
        exit(1)
    }

    let gotStatus = waitForStatus(client, timeout: options.timeout)
    if let status = client.lastStatus, gotStatus {
        print("STATUS \(status.rawHex)")
        print("PHASE \(status.phaseCodeHex) \(status.phaseLabel)")
        print("ISSUE \(status.issueCodeHex) \(status.issueLabel)")
        print("READY \(status.isReadyForNextJob)")
        client.disconnect()
        exit(0)
    }
    printError("No status received.")
    client.disconnect()
    exit(1)
}

func runPrint(path: String, options: CLIOptions) {
    let url = URL(fileURLWithPath: path)
    guard FileManager.default.fileExists(atPath: url.path) else {
        printError("File not found: \(path)")
        exit(1)
    }

    guard let image = NSImage(contentsOf: url) else {
        printError("Unable to load image: \(path)")
        exit(1)
    }

    let pipeline = ImagePipeline()
    let jpegData: Data
    do {
        jpegData = try pipeline.makePrintableJPEG(from: image, offset: .zero, zoom: 1.0, quality: 0.98)
    } catch {
        printError("Image processing failed: \(error.localizedDescription)")
        exit(1)
    }

    let client = HiPrintBLEClient(targetNamePrefix: options.namePrefix)
    client.connect()
    guard waitForConnection(client, timeout: options.timeout) else {
        printError("Failed to connect.")
        exit(1)
    }

    let start = client.send(jpeg: jpegData, paceMs: options.paceMs, timeout: max(options.timeout, 90))
    switch start {
    case .started:
        break
    case .rejected(let reason):
        printError("Print rejected: \(reason)")
        client.disconnect()
        exit(1)
    }

    let completed = waitForPrint(client, timeout: max(options.timeout, 90))
    if completed {
        print("PRINT_DONE")
        client.disconnect()
        exit(0)
    }
    printError("Print failed or timed out.")
    client.disconnect()
    exit(1)
}

func waitForConnection(_ client: HiPrintBLEClient, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        switch client.connectionState {
        case .connected:
            return true
        case .failed:
            return false
        default:
            break
        }
    }
    return false
}

func waitForStatus(_ client: HiPrintBLEClient, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        if client.lastStatus != nil { return true }
        if case .failed = client.connectionState { return false }
    }
    return false
}

func waitForPrint(_ client: HiPrintBLEClient, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    var lastBucket = -1
    while Date() < deadline {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.1))
        if case .failed = client.connectionState { return false }

        if let outcome = client.sendOutcome {
            switch outcome {
            case .completed:
                return true
            case .failed:
                return false
            }
        }

        let progress = client.sendProgress
        let bucket = Int(progress * 10)
        if bucket != lastBucket {
            lastBucket = bucket
            print(String(format: "PROGRESS %d%%", min(100, bucket * 10)))
        }
    }

    if let outcome = client.sendOutcome, case .completed = outcome {
        return true
    }
    return false
}

func printError(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}
