import SwiftUI

@main
struct TelechApp: App {
    @StateObject private var store = PlayerStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
