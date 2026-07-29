@preconcurrency import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    private var activity: Activity<GinnyLiveActivityAttributes>?

    private init() {
        activity = Activity<GinnyLiveActivityAttributes>.activities.first
    }

    func start(conversationID: UUID, model: String, thinkingLevel: String) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = GinnyLiveActivityAttributes(
            conversationID: conversationID,
            model: model
        )
        let state = GinnyLiveActivityAttributes.ContentState(
            status: .thinking,
            detail: "Thinking · \(thinkingLevel)",
            startedAt: Date()
        )

        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        )
    }

    func update(status: GinnyLiveActivityAttributes.ContentState.Status, detail: String) async {
        guard let activity else { return }

        let state = GinnyLiveActivityAttributes.ContentState(
            status: status,
            detail: detail,
            startedAt: activity.content.state.startedAt
        )
        await activity.update(ActivityContent(state: state, staleDate: nil))
    }

    func end(status: GinnyLiveActivityAttributes.ContentState.Status, detail: String) async {
        guard let activity else { return }

        let state = GinnyLiveActivityAttributes.ContentState(
            status: status,
            detail: detail,
            startedAt: activity.content.state.startedAt
        )
        await activity.end(
            ActivityContent(state: state, staleDate: nil),
            dismissalPolicy: .immediate
        )
        self.activity = nil
    }
}
