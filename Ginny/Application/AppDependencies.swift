import Foundation

/// Application-lifetime dependencies are constructed at the composition root.
struct AppDependencies: Sendable {
    static let live = AppDependencies()
}
