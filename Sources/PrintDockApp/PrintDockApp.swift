import SwiftUI

@main
struct PrintDockApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .background(Theme.background)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
