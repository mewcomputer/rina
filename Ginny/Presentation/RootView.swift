import SwiftUI

struct RootView: View {
    let dependencies: AppDependencies
    @ObservedObject var themeStore: ThemeStore

    var body: some View {
        NavigationStack {
            ChatView(dependencies: dependencies, themeStore: themeStore)
        }
    }
}

#Preview {
    if let dependencies = try? AppDependencies.makeLive() {
        RootView(dependencies: dependencies, themeStore: ThemeStore())
    } else {
        Text("Ginny could not start")
    }
}
