import SwiftUI

struct RootView: View {
    let dependencies: AppDependencies

    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Your workspace is ready",
                systemImage: "square.stack.3d.up",
                description: Text("Conversations, artefacts, sources, and contexts will live here.")
            )
            .navigationTitle("Ginny")
        }
    }
}

#Preview {
    RootView(dependencies: .live)
}
