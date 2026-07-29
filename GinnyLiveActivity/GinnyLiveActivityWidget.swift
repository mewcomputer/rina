import ActivityKit
import SwiftUI
import WidgetKit

struct GinnyLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GinnyLiveActivityAttributes.self) { context in
            GinnyLiveActivityLockScreenView(context: context)
                .activityBackgroundTint(Color.black)
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.model)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Label(context.state.detail, systemImage: context.state.status.symbolName)
                        .font(.caption)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "sparkles")
            }
        }
    }
}

private struct GinnyLiveActivityLockScreenView: View {
    let context: ActivityViewContext<GinnyLiveActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: context.state.status.symbolName)
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 3) {
                Text(context.attributes.model)
                    .font(.headline)
                    .lineLimit(1)
                Text(context.state.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(context.state.startedAt, style: .timer)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private extension GinnyLiveActivityAttributes.ContentState.Status {
    var symbolName: String {
        switch self {
        case .thinking: "sparkles"
        case .usingTool: "wrench.and.screwdriver"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }
}

@main
struct GinnyLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        GinnyLiveActivityWidget()
    }
}
