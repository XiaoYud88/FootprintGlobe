import SwiftUI

@main
@MainActor
struct FootprintGlobeApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(app)
                .preferredColorScheme(.dark)
                .tint(Theme.brand)
        }
    }
}
