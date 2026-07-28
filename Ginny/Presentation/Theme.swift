import Foundation
import SwiftUI

enum GinnyThemeMode: String, Decodable {
    case dark
    case light

    var colorScheme: ColorScheme {
        switch self {
        case .dark:
            .dark
        case .light:
            .light
        }
    }
}

struct ThemeDefinition: Decodable {
    let mode: GinnyThemeMode
    let base: String?
    let tokens: [String: String]

    init(mode: GinnyThemeMode, base: String?, tokens: [String: String]) {
        self.mode = mode
        self.base = base
        self.tokens = tokens
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(GinnyThemeMode.self, forKey: .mode)
        base = try container.decodeIfPresent(String.self, forKey: .base)
        tokens = try container.decodeIfPresent([String: String].self, forKey: .tokens) ?? [:]
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case base
        case tokens
    }
}

struct ThemeManifest: Decodable {
    let version: Int
    let tokens: [String: String]
    let themes: [String: ThemeDefinition]

    func theme(named requestedID: String) -> GinnyTheme {
        let id = themes[requestedID] == nil ? "dark" : requestedID
        guard let definition = themes[id] else {
            return GinnyTheme(id: id, mode: .dark, tokens: tokens)
        }

        return GinnyTheme(
            id: id,
            mode: definition.mode,
            tokens: mergedTokens(for: id, visited: [])
        )
    }

    private func mergedTokens(for id: String, visited: Set<String>) -> [String: String] {
        guard !visited.contains(id), let definition = themes[id] else {
            return tokens
        }

        var merged = definition.base.map {
            mergedTokens(for: $0, visited: visited.union([id]))
        } ?? tokens
        merged.merge(definition.tokens) { _, override in override }
        return merged
    }
}

struct GinnyTheme {
    let id: String
    let mode: GinnyThemeMode
    private let tokens: [String: String]

    init(id: String, mode: GinnyThemeMode, tokens: [String: String]) {
        self.id = id
        self.mode = mode
        self.tokens = tokens
    }

    func color(_ token: String) -> Color {
        guard let hex = hexValue(for: token) else { return .clear }
        return Color(hex: hex)
    }

    func hexValue(for token: String) -> String? {
        resolve(token: token, visited: [])
    }

    private func resolve(token: String, visited: Set<String>) -> String? {
        let key = token.hasPrefix("@") ? String(token.dropFirst()) : token
        guard !visited.contains(key), let value = tokens[key] else {
            return token.hasPrefix("#") ? token : nil
        }

        if value.hasPrefix("@") {
            return resolve(token: value, visited: visited.union([key]))
        }
        return value
    }
}

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        let normalized = value.count == 6 ? "FF\(value)" : value
        let number = UInt64(normalized, radix: 16) ?? 0
        self.init(
            .sRGB,
            red: Double((number >> 16) & 0xFF) / 255,
            green: Double((number >> 8) & 0xFF) / 255,
            blue: Double(number & 0xFF) / 255,
            opacity: Double((number >> 24) & 0xFF) / 255
        )
    }
}

@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var selectedThemeID: String

    let manifest: ThemeManifest
    private let defaults: UserDefaults

    init(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        if let url = bundle.url(forResource: "theme_manifest", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let manifest = try? JSONDecoder().decode(ThemeManifest.self, from: data)
        {
            self.manifest = manifest
        } else {
            self.manifest = ThemeManifest(
                version: 1,
                tokens: [
                    "background": "#1e1e21",
                    "foreground": "#ffffff",
                    "text.body": "@foreground",
                    "text.muted": "#a9a9a9",
                    "text.error": "#ffb4ab",
                    "card": "#323238",
                    "secondary": "#323238",
                    "border": "#323237",
                    "primary": "#00ffff",
                    "primary_foreground": "#1e1e21",
                    "muted": "#28282c",
                    "red.bg": "#5c2626",
                    "pill.custom.fg": "@foreground",
                    "pill.custom.bg": "@muted",
                    "markdown.paragraph": "@text.body",
                    "markdown.heading.foreground": "@text.body",
                    "markdown.block_quote": "@text.muted",
                    "markdown.list_bullet": "@text.muted",
                    "markdown.strong": "@text.body",
                    "markdown.link_text": "@primary",
                    "markdown.inline_code.fg": "@text.body",
                    "markdown.inline_code.bg": "@muted",
                    "markdown.code_fence.border": "@border",
                    "markdown.thematic_break": "@border"
                ],
                themes: ["dark": ThemeDefinition(mode: .dark, base: nil, tokens: [:])]
            )
        }
        selectedThemeID = defaults.string(forKey: "theme.id") ?? "dark"
    }

    var theme: GinnyTheme {
        manifest.theme(named: selectedThemeID)
    }

    var availableThemeIDs: [String] {
        manifest.themes.keys.sorted()
    }

    func displayName(for themeID: String) -> String {
        themeID
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    func select(themeID: String) {
        guard manifest.themes[themeID] != nil else { return }
        selectedThemeID = themeID
        defaults.set(themeID, forKey: "theme.id")
    }
}

private struct GinnyThemeKey: EnvironmentKey {
    static let defaultValue = GinnyTheme(
        id: "dark",
        mode: .dark,
        tokens: [
            "background": "#1e1e21",
            "foreground": "#ffffff",
            "primary": "#00ffff",
            "card": "#323238",
            "muted_foreground": "#a9a9a9"
        ]
    )
}

extension EnvironmentValues {
    var ginnyTheme: GinnyTheme {
        get { self[GinnyThemeKey.self] }
        set { self[GinnyThemeKey.self] = newValue }
    }
}
