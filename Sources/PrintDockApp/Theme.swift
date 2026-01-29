import SwiftUI

enum Theme {
    static let background = dynamic(
        light: NSColor(calibratedWhite: 0.96, alpha: 1.0),
        dark: NSColor(calibratedWhite: 0.12, alpha: 1.0)
    )
    static let card = dynamic(
        light: NSColor(calibratedWhite: 0.98, alpha: 1.0),
        dark: NSColor(calibratedWhite: 0.18, alpha: 1.0)
    )
    static let panel = dynamic(
        light: NSColor(calibratedWhite: 0.94, alpha: 1.0),
        dark: NSColor(calibratedWhite: 0.16, alpha: 1.0)
    )
    static let canvas = dynamic(
        light: NSColor(calibratedWhite: 0.99, alpha: 1.0),
        dark: NSColor(calibratedWhite: 0.11, alpha: 1.0)
    )
    static let accent = Color(nsColor: .systemOrange)
    static let ink = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let border = dynamic(
        light: NSColor(calibratedWhite: 0.86, alpha: 1.0),
        dark: NSColor(calibratedWhite: 0.25, alpha: 1.0)
    )
    static let shadow = Color.black.opacity(0.18)

    private static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
