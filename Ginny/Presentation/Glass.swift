import SwiftUI

enum GinnyGlassProminence {
    case subtle
    case elevated

    var tintOpacity: Double {
        switch self {
        case .subtle:
            0.18
        case .elevated:
            0.32
        }
    }

    var shadowRadius: CGFloat {
        switch self {
        case .subtle:
            10
        case .elevated:
            22
        }
    }
}

private struct GinnyGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    let prominence: GinnyGlassProminence
    @Environment(\.ginnyTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        Group {
            if reduceTransparency {
                content
                    .background(theme.color("card"), in: shape)
                    .overlay {
                        shape.stroke(theme.color("border").opacity(0.9), lineWidth: 1)
                    }
            } else {
                content.glassEffect(
                    .regular
                        .tint(theme.color("card").opacity(prominence.tintOpacity))
                        .interactive(),
                    in: shape
                )
            }
        }
        .shadow(
            color: .black.opacity(0.16),
            radius: prominence.shadowRadius,
            y: prominence == .elevated ? 8 : 4
        )
    }
}

extension View {
    func ginnyGlass<S: Shape>(
        _ shape: S,
        prominence: GinnyGlassProminence = .subtle
    ) -> some View {
        modifier(GinnyGlassModifier(shape: shape, prominence: prominence))
    }
}
