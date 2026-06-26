import SwiftUI

@main
struct GreenDeckApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(state)
                .preferredColorScheme(.dark)
        }
    }
}
