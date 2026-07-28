import SwiftUI

@main
struct GinnyApp: App {
    private let dependencies = AppDependencies.live

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
        }
    }
}
