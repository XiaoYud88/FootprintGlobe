import SwiftUI

struct FootprintGlobeApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
        }
    }
}

/// 根视图只做一件事：把「设置里选的主题」应用到整个 App。
/// 用户明确要求不跟随系统，所以这里读的是 `Theme.colorScheme`（由 AppModel.appearance 决定）。
struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        HomeView()
            .preferredColorScheme(Theme.colorScheme)
            .tint(Theme.brand)
    }
}
