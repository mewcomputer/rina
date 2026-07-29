import ActivityKit
import Foundation

struct GinnyLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Status: String, Codable, Hashable {
            case thinking
            case usingTool
            case completed
            case cancelled
            case failed
        }

        let status: Status
        let detail: String
        let startedAt: Date
    }

    let conversationID: UUID
    let model: String
}
