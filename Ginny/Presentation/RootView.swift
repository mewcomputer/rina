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
    RootView(dependencies: .live, themeStore: ThemeStore())
}
