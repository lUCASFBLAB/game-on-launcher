import SwiftUI

/// Design tokens for the whole launcher.
///
/// The palette is built around a deep "deep space" base with a single neon accent.
/// Everything else is derived from these tokens so a theme switch stays coherent.
enum Theme {
    // MARK: - Core palette

    /// Base canvas colour (deep space).
    static let void = Color(red: 0.027, green: 0.035, blue: 0.063)
    static let abyss = Color(red: 0.043, green: 0.055, blue: 0.094)
    static let nebula = Color(red: 0.071, green: 0.086, blue: 0.137)

    /// Surface colours used by panels.
    static let surface = Color(red: 0.094, green: 0.110, blue: 0.161)
    static let surfaceRaised = Color(red: 0.125, green: 0.145, blue: 0.204)

    /// Text colours.
    static let textPrimary = Color(red: 0.957, green: 0.969, blue: 0.988)
    static let textSecondary = Color(red: 0.635, green: 0.678, blue: 0.749)
    static let textTertiary = Color(red: 0.427, green: 0.475, blue: 0.553)

    /// Semantic colours.
    static let success = Color(red: 0.208, green: 0.827, blue: 0.600)
    static let warning = Color(red: 0.984, green: 0.749, blue: 0.141)
    static let danger = Color(red: 0.937, green: 0.325, blue: 0.373)
    static let info = Color(red: 0.298, green: 0.647, blue: 0.976)

    // MARK: - Accent presets

    struct AccentPreset: Identifiable, Hashable {
        let id: String
        let name: String
        let primary: Color
        let secondary: Color
        let symbol: String
    }

    static let accents: [AccentPreset] = [
        AccentPreset(id: "plasma", name: "Plasma", primary: Color(red: 0.976, green: 0.310, blue: 0.420), secondary: Color(red: 0.596, green: 0.345, blue: 0.976), symbol: "bolt.fill"),
        AccentPreset(id: "cyan", name: "Ciano", primary: Color(red: 0.145, green: 0.831, blue: 0.925), secondary: Color(red: 0.325, green: 0.482, blue: 0.976), symbol: "drop.fill"),
        AccentPreset(id: "viridian", name: "Viridiano", primary: Color(red: 0.145, green: 0.851, blue: 0.596), secondary: Color(red: 0.157, green: 0.694, blue: 0.898), symbol: "leaf.fill"),
        AccentPreset(id: "solar", name: "Solar", primary: Color(red: 0.988, green: 0.741, blue: 0.180), secondary: Color(red: 0.976, green: 0.388, blue: 0.212), symbol: "sun.max.fill"),
        AccentPreset(id: "orchid", name: "Orquídea", primary: Color(red: 0.729, green: 0.361, blue: 0.973), secondary: Color(red: 0.937, green: 0.318, blue: 0.643), symbol: "sparkle"),
        AccentPreset(id: "frost", name: "Gelo", primary: Color(red: 0.635, green: 0.851, blue: 0.973), secondary: Color(red: 0.396, green: 0.847, blue: 0.729), symbol: "snowflake"),
        AccentPreset(id: "ember", name: "Brasa", primary: Color(red: 0.976, green: 0.416, blue: 0.180), secondary: Color(red: 0.863, green: 0.212, blue: 0.298), symbol: "flame.fill"),
        AccentPreset(id: "graphite", name: "Grafite", primary: Color(red: 0.729, green: 0.757, blue: 0.812), secondary: Color(red: 0.396, green: 0.427, blue: 0.490), symbol: "circle.hexagongrid.fill")
    ]

    // MARK: - Seasonal themes

    struct SeasonalTheme: Identifiable, Hashable {
        let id: String
        let name: String
        let emoji: String
        let primary: Color
        let secondary: Color
        let symbol: String
    }

    static let seasonalThemes: [SeasonalTheme] = [
        SeasonalTheme(id: "Noite neon", name: "Noite neon", emoji: "✨", primary: Color(red: 0.976, green: 0.310, blue: 0.420), secondary: Color(red: 0.596, green: 0.345, blue: 0.976), symbol: "sparkles"),
        SeasonalTheme(id: "Natal", name: "Natal", emoji: "🎄", primary: Color(red: 0.180, green: 0.820, blue: 0.482), secondary: Color(red: 0.902, green: 0.259, blue: 0.310), symbol: "gift.fill"),
        SeasonalTheme(id: "Halloween", name: "Halloween", emoji: "🎃", primary: Color(red: 1.000, green: 0.451, blue: 0.110), secondary: Color(red: 0.639, green: 0.212, blue: 0.831), symbol: "wand.and.stars"),
        SeasonalTheme(id: "Ano Novo", name: "Ano Novo", emoji: "🎆", primary: Color(red: 0.290, green: 0.722, blue: 1.000), secondary: Color(red: 0.702, green: 0.400, blue: 0.980), symbol: "sparkles"),
        SeasonalTheme(id: "Páscoa", name: "Páscoa", emoji: "🐣", primary: Color(red: 0.769, green: 0.482, blue: 0.949), secondary: Color(red: 0.400, green: 0.855, blue: 0.741), symbol: "hare.fill"),
        SeasonalTheme(id: "Verão", name: "Verão", emoji: "☀️", primary: Color(red: 0.161, green: 0.808, blue: 0.878), secondary: Color(red: 0.976, green: 0.769, blue: 0.278), symbol: "sun.max.fill"),
        SeasonalTheme(id: "Carnaval", name: "Carnaval", emoji: "🎭", primary: Color(red: 0.961, green: 0.271, blue: 0.639), secondary: Color(red: 0.310, green: 0.702, blue: 0.980), symbol: "theatermasks.fill")
    ]

    // MARK: - Metrics

    static let panelRadius: CGFloat = 18
    static let controlRadius: CGFloat = 12
    static let smallRadius: CGFloat = 9
    static let gutter: CGFloat = 26
    static let sidebarWidth: CGFloat = 232
    static let collapsedSidebarWidth: CGFloat = 74

    /// Standard spacing scale.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 30
    }
}

// MARK: - Theme resolution

/// Resolved visual tokens for the current app state.
struct ThemeTokens {
    var accent: Color
    var accentSecondary: Color
    var base: Color
    var surface: Color
    var textPrimary: Color
    var textSecondary: Color
    var isDark: Bool

    static func resolve(accentID: String, isDark: Bool, seasonalID: String, seasonalEnabled: Bool) -> ThemeTokens {
        let preset = Theme.accents.first { $0.id == accentID } ?? Theme.accents[0]
        var primary = preset.primary
        var secondary = preset.secondary
        if seasonalEnabled, let season = Theme.seasonalThemes.first(where: { $0.id == seasonalID }), season.id != "Noite neon" {
            primary = season.primary
            secondary = season.secondary
        }
        return ThemeTokens(
            accent: primary,
            accentSecondary: secondary,
            base: isDark ? Theme.void : Color(red: 0.937, green: 0.949, blue: 0.965),
            surface: isDark ? Theme.surface : Color.white,
            textPrimary: isDark ? Theme.textPrimary : Color(red: 0.071, green: 0.086, blue: 0.125),
            textSecondary: isDark ? Theme.textSecondary : Color(red: 0.353, green: 0.396, blue: 0.471),
            isDark: isDark
        )
    }
}

// MARK: - Reusable shapes

/// Rounded rectangle with a continuously adjustable corner radius.
struct SquircleShape: InsettableShape {
    var radius: CGFloat
    var insetAmount: CGFloat = 0

    init(radius: CGFloat) { self.radius = radius }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        path.addRoundedRect(in: rect.insetBy(dx: insetAmount, dy: insetAmount), cornerSize: CGSize(width: r, height: r), style: .continuous)
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
