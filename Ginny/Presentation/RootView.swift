import SwiftUI

struct RootView: View {
    let dependencies: AppDependencies

    var body: some View {
        NavigationStack {
            ChatView()
        }
    }
}

#Preview {
    RootView(dependencies: .live)
}
