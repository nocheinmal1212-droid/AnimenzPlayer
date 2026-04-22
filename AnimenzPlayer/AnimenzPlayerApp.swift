import SwiftUI

@main
struct AnimenzPlayerApp: App {
    @StateObject private var player = PlayerViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(player)
                .frame(minWidth: 500, minHeight: 600)
        }
        #if os(macOS)
        .windowStyle(.hiddenTitleBar)
        #endif
    }
}
