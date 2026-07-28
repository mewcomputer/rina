import SwiftUI

enum GinnyGlassProminence {
    case subtle
    case elevated

    var tintOpacity: Double {
        switch self {
        case .subtle:
            0.28
        case .elevated:
            0.48
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
        content
            .background {
                if reduceTransparency {
                    shape.fill(theme.color("card"))
                } else {
                    shape.fill(.regularMaterial)
                }
            }
            .overlay {
                shape.fill(theme.color("card").opacity(prominence.tintOpacity))
            }
            .overlay {
                shape.stroke(theme.color("border").opacity(0.78), lineWidth: 1)
            }
            .shadow(
                color: .black.opacity(0.18),
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
