import SwiftUI

@main
@MainActor
struct GinnyApp: App {
    private let dependencies: AppDependencies?
    private let startupError: String?
    @StateObject private var themeStore = ThemeStore()

    init() {
        do {
            dependencies = try AppDependencies.makeLive()
            startupError = nil
        } catch {
            dependencies = nil
            startupError = "Ginny couldn’t access its local storage."
        }
    }

    var body: some Scene {
        WindowGroup {
            if let dependencies {
                RootView(dependencies: dependencies, themeStore: themeStore)
                    .environment(\.ginnyTheme, themeStore.theme)
                    .preferredColorScheme(themeStore.theme.mode.colorScheme)
            } else {
                VStack(spacing: 12) {
                    Text("Ginny couldn’t start")
                        .font(.title2.weight(.semibold))
                    Text(startupError ?? "Local storage is unavailable.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
            }
        }
    }
}
