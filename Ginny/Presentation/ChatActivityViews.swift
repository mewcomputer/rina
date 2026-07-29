import SwiftStreamingMarkdown
import SwiftUI

enum ThinkingIndicatorSymbol: String, CaseIterable {
    case sparkle
    case starFill = "star.fill"
    case asterisk

    static func next(after symbol: Self) -> Self {
        let symbols = allCases
        guard let index = symbols.firstIndex(of: symbol) else { return symbols[0] }
        return symbols[(index + 1) % symbols.count]
    }
}

struct CitationGroupView: View {
    let citations: [Citation]
    @Environment(\.ginnyTheme) private var theme

    init(payload: String) {
        guard let data = payload.data(using: .utf8) else {
            citations = []
            return
        }
        citations = (try? JSONDecoder().decode([Citation].self, from: data)) ?? []
    }

    init(citations: [Citation]) {
        self.citations = citations
    }

    var body: some View {
        if citations.isEmpty {
            Text("Sources unavailable")
                .font(.footnote)
                .foregroundStyle(theme.color("text.muted"))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Sources", systemImage: "link")
                    .font(.subheadline.weight(.semibold))
                ForEach(citations) { citation in
                    if let url = URL(string: citation.url) {
                        Link(destination: url) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(citation.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(2)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(citation.url)
                                    .font(.caption)
                                    .foregroundStyle(theme.color("text.muted"))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(12)
            .background(
                theme.color("card").opacity(0.25),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
    }
}

struct ThinkingDisclosureView: View {
    let snapshot: String
    let isRedacted: Bool
    let markdownConfig: MarkdownRenderConfig
    @Environment(\.ginnyTheme) private var theme
    @State private var isExpanded = false
    @StateObject private var source = ChatResponseSource()

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Group {
                if snapshot.isEmpty, isRedacted {
                    Text("Reasoning is hidden by the provider.")
                        .font(.footnote)
                        .foregroundStyle(theme.color("text.muted"))
                } else {
                    StreamedMarkdownView(
                        source: source,
                        config: markdownConfig
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                ThinkingIndicator(isAnimating: false)
                Text("Thinking")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(theme.color("text.muted"))
        }
        .tint(theme.color("text.body"))
        .onAppear {
            source.yield(snapshot)
        }
        .onChange(of: snapshot) { _, snapshot in
            source.yield(snapshot)
        }
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                source.replayLatest()
            }
        }
    }
}

struct LiveThinkingDisclosureView: View {
    let source: ChatResponseSource
    let markdownConfig: MarkdownRenderConfig
    let isComplete: Bool
    @Environment(\.ginnyTheme) private var theme
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            StreamedMarkdownView(
                source: source,
                config: markdownConfig
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        } label: {
            HStack(spacing: 8) {
                ThinkingIndicator(isAnimating: !isComplete)
                Text("Thinking")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(theme.color("text.muted"))
        }
        .tint(theme.color("text.body"))
        .onChange(of: isExpanded) { _, expanded in
            if expanded {
                source.replayLatest()
            }
        }
        .onChange(of: isComplete) { _, complete in
            if complete {
                withAnimation(.easeOut(duration: 0.18)) {
                    isExpanded = false
                }
            }
        }
    }
}

struct ThinkingIndicator: View {
    let isAnimating: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.ginnyTheme) private var theme
    @State private var symbol: ThinkingIndicatorSymbol = .sparkle
    @State private var rotationAnchor = Date.now
    @State private var rotationAtAnchor: Double = 0
    @State private var degreesPerSecond: Double = 0

    private let slowSpeed: Double = 18
    private let burstSpeed: Double = 280

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: 1.0 / 60.0,
                paused: !isAnimating || reduceMotion
            )
        ) { timeline in
            Image(systemName: symbol.rawValue)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.color("text.muted"))
                .frame(width: 20, height: 20)
                .contentTransition(.symbolEffect(.replace))
                .rotationEffect(
                    .degrees(
                        reduceMotion
                            ? 0
                            : rotation(at: timeline.date)
                    )
                )
        }
        .accessibilityHidden(true)
        .onChange(of: isAnimating, initial: true) { _, isAnimating in
            updateRotationSpeed(
                to: isAnimating && !reduceMotion ? slowSpeed : 0
            )
        }
        .onChange(of: reduceMotion) { _, reduceMotion in
            updateRotationSpeed(
                to: isAnimating && !reduceMotion ? slowSpeed : 0
            )
        }
        .task(id: isAnimating && !reduceMotion) {
            guard isAnimating, !reduceMotion else { return }

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(2100))
                guard !Task.isCancelled else { return }

                updateRotationSpeed(to: burstSpeed)

                withAnimation(.easeInOut(duration: 0.42)) {
                    symbol = .next(after: symbol)
                }

                try? await Task.sleep(for: .milliseconds(420))
                guard !Task.isCancelled else { return }

                updateRotationSpeed(to: slowSpeed)
            }
        }
    }

    private func rotation(at date: Date) -> Double {
        let elapsed = date.timeIntervalSince(rotationAnchor)

        return (
            rotationAtAnchor +
            elapsed * degreesPerSecond
        )
        .truncatingRemainder(dividingBy: 360)
    }

    private func updateRotationSpeed(to newSpeed: Double) {
        let now = Date.now

        rotationAtAnchor = rotation(at: now)
        rotationAnchor = now
        degreesPerSecond = newSpeed
    }
}

struct ToolActivityGroupView: View {
    let group: ToolActivityGroup
    let citations: [Citation]
    @Environment(\.ginnyTheme) private var theme
    @State private var isExpanded = false

    init(group: ToolActivityGroup, citations: [Citation] = []) {
        self.group = group
        self.citations = citations
    }

    private var containsError: Bool {
        group.activities.contains { $0.result?.attributes["isError"] == "true" }
            || group.unmatchedResults.contains { $0.attributes["isError"] == "true" }
    }

    private var isPending: Bool {
        group.activities.contains { !$0.call.isComplete || $0.result == nil }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 0) {
                if isSearchActivity {
                    SearchActivityDetailsView(group: group, citations: citations)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(group.activities) { activity in
                            ToolActivityRow(activity: activity)
                        }
                        ForEach(group.unmatchedResults, id: \.id) { result in
                            ToolResultRow(result: result)
                        }
                        if !citations.isEmpty {
                            CitationGroupView(citations: citations)
                        }
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSearchActivity ? "magnifyingglass" : "wrench.and.screwdriver")
                    .font(.subheadline.weight(.medium))
                Text(activityLabel)
                    .font(.subheadline.weight(.medium))
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                if isPending {
                    ThinkingIndicator(isAnimating: true)
                } else if containsError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(theme.color("text.error"))
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.color("text.success"))
                }
            }
        }
        .tint(theme.color("text.body"))
        .padding(14)
        .background(
            theme.color("card").opacity(0.3),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }

    private var activityLabel: String {
        guard !citations.isEmpty, !isPending, !containsError else {
            return toolActivityLabel(for: group)
        }
        return citationActivitySummary(citations)
    }

    private var isSearchActivity: Bool {
        !group.activities.isEmpty && group.activities.allSatisfy {
            $0.call.attributes["name"] == "search_web"
                || $0.call.attributes["name"] == "search_workspace"
        }
    }
}

private struct SearchActivityDetailsView: View {
    let group: ToolActivityGroup
    let citations: [Citation]
    @Environment(\.ginnyTheme) private var theme

    private var queries: [String] {
        group.activities.compactMap { activity in
            guard let data = activity.call.payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { return nil }
            return object["query"] as? String
        }
    }

    private var resultCount: Int? {
        for activity in group.activities {
            guard let result = activity.result,
                  let data = result.payload.data(using: .utf8)
            else { continue }
            if let response = try? JSONDecoder().decode(WebSearchResponse.self, from: data) {
                return response.results.count
            }
            if let results = try? JSONDecoder().decode([SearchResult].self, from: data) {
                return results.count
            }
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(queries, id: \.self) { query in
                Label {
                    Text("“\(query)”")
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
                .font(.caption)
                .foregroundStyle(theme.color("text.muted"))
            }

            if !citations.isEmpty {
                CitationGroupView(citations: citations)
            } else if let resultCount {
                Text(resultCount == 0 ? "No items found" : "Found \(resultCount) items")
                    .font(.footnote)
                    .foregroundStyle(theme.color("text.muted"))
            } else {
                ForEach(group.activities.compactMap(\.result), id: \.id) { result in
                    if result.attributes["isError"] == "true" {
                        ToolResultRow(result: result)
                    }
                }
            }
        }
    }
}

func citationActivitySummary(_ citations: [Citation]) -> String {
    var domains: [String] = []
    for citation in citations {
        guard let host = URL(string: citation.url)?.host,
              !host.isEmpty
        else { continue }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if !domains.contains(domain) {
            domains.append(domain)
        }
    }

    guard !domains.isEmpty else { return "Found items" }
    let visibleDomains = Array(domains.prefix(3))
    let domainText: String
    switch visibleDomains.count {
    case 1:
        domainText = visibleDomains[0]
    case 2:
        domainText = "\(visibleDomains[0]) and \(visibleDomains[1])"
    default:
        domainText = visibleDomains.dropLast().joined(separator: ", ")
            + ", and \(visibleDomains.last!)"
    }
    let suffix = domains.count > 3 ? ", and more" : ""
    return "Found items from \(domainText)\(suffix)"
}

struct ToolApprovalView: View {
    let request: ToolApprovalRequest
    let approve: () -> Void
    let deny: () -> Void
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Approve tool", systemImage: "hand.raised")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(theme.color("text.body"))

            Text(request.name)
                .font(.body.weight(.semibold))

            if !request.arguments.isEmpty {
                Text(request.arguments)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.color("text.muted"))
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button("Deny", action: deny)
                    .buttonStyle(.bordered)
                Button("Approve", action: approve)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .ginnyGlass(
            RoundedRectangle(cornerRadius: 14, style: .continuous),
            prominence: .subtle
        )
    }
}

private struct ToolActivityRow: View {
    let activity: ToolActivity
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ToolCallRow(call: activity.call)

            if let result = activity.result {
                Divider()
                    .overlay(theme.color("border").opacity(0.7))
                ToolResultRow(result: result)
            }
        }
    }
}

private struct ToolCallRow: View {
    let call: ContentBlock
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        let name = call.attributes["name"] ?? "Tool"

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: call.isComplete ? "checkmark" : "ellipsis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(
                        call.isComplete
                            ? theme.color("text.success")
                            : theme.color("text.muted")
                    )
                Text(name.isEmpty ? "Tool" : name)
                    .font(.subheadline.weight(.medium))
            }

            if !call.payload.isEmpty {
                Text(call.payload)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme.color("text.muted"))
                    .textSelection(.enabled)
            }
        }
    }
}

private struct ToolResultRow: View {
    let result: ContentBlock
    @Environment(\.ginnyTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Result", systemImage: "arrow.turn.down.right")
                .font(.caption.weight(.medium))
                .foregroundStyle(
                    result.attributes["isError"] == "true"
                        ? theme.color("text.error")
                        : theme.color("text.muted")
                )

            Text(result.payload)
                .font(.caption.monospaced())
                .foregroundStyle(theme.color("text.muted"))
                .textSelection(.enabled)
        }
    }
}

struct ToolResultGroupView: View {
    let results: [ContentBlock]
    @Environment(\.ginnyTheme) private var theme
    @State private var isExpanded = false

    private var containsError: Bool {
        results.contains { $0.attributes["isError"] == "true" }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(results, id: \.id) { result in
                    ToolResultRow(result: result)
                }
            }
            .padding(.top, 10)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: containsError ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.subheadline.weight(.medium))
                Text(results.count == 1 ? "Tool result" : "Tool results")
                    .font(.subheadline.weight(.medium))
            }
        }
        .tint(containsError ? theme.color("text.error") : theme.color("text.body"))
        .padding(14)
        .background(
            (containsError ? theme.color("surface.error") : theme.color("card")).opacity(0.3),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
    }
}
