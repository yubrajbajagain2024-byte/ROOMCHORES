import SwiftUI

/// One place for colour and spacing, so screens added later still look like the app.
enum Theme {

    // MARK: - Palette

    static let indigo = Color(red: 0.29, green: 0.32, blue: 0.53)
    static let violet = Color(red: 0.45, green: 0.36, blue: 0.68)
    static let sky    = Color(red: 0.31, green: 0.58, blue: 0.82)
    static let teal   = Color(red: 0.25, green: 0.65, blue: 0.62)
    static let green  = Color(red: 0.32, green: 0.66, blue: 0.42)
    static let amber  = Color(red: 0.87, green: 0.63, blue: 0.22)
    static let rose   = Color(red: 0.84, green: 0.38, blue: 0.40)
    static let slate  = Color(red: 0.44, green: 0.47, blue: 0.54)

    // MARK: - Feed

    /// Action colour: links, the wordmark, primary buttons.
    static let brand = adaptive(light: (0.031, 0.400, 1.000), dark: (0.176, 0.533, 1.000))
    /// The grey behind the cards.
    static let feedBackground = adaptive(light: (0.910, 0.918, 0.929), dark: (0.094, 0.098, 0.102))
    static let feedCard = adaptive(light: (1.000, 1.000, 1.000), dark: (0.141, 0.145, 0.149))
    /// Round icon buttons and input pills.
    static let chipFill = adaptive(light: (0.894, 0.902, 0.922), dark: (0.227, 0.231, 0.235))
    static let secondaryText = adaptive(light: (0.396, 0.404, 0.420), dark: (0.690, 0.702, 0.722))
    static let hairline = adaptive(light: (0.808, 0.816, 0.831), dark: (0.243, 0.247, 0.251))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }

    /// Distinct colours for roommate avatars, ordered so the first few stay far apart.
    static let memberPalette: [Color] = [indigo, amber, teal, rose, violet, green, sky, slate]

    static func memberColor(_ index: Int) -> Color {
        memberPalette[abs(index) % memberPalette.count]
    }

    // MARK: - Semantics

    static func qualityColor(_ score: Double) -> Color {
        switch score {
        case ..<2.0: return rose
        case ..<3.0: return amber
        case ..<4.0: return green
        default:     return teal
        }
    }

    // MARK: - Layout

    static let corner: CGFloat = 16
    static let cardPadding: CGFloat = 16
}

// MARK: - Card

/// The standard raised surface. Uses the grouped-background material so it reads
/// correctly in both light and dark without a second palette.
struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }
}

extension View {
    func card(padding: CGFloat = Theme.cardPadding) -> some View {
        modifier(CardModifier(padding: padding))
    }
}
