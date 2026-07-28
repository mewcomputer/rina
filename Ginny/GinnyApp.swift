import SwiftUI

@main
struct GinnyApp: App {
    private let dependencies = AppDependencies.live
    @StateObject private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies, themeStore: themeStore)
                .environment(\.ginnyTheme, themeStore.theme)
                .preferredColorScheme(themeStore.theme.mode.colorScheme)
        }
    }
}
