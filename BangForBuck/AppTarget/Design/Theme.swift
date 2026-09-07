//
//  Theme.swift
//  ABV
//
//  Created by Noval, Cameron on 9/7/26.
//


import SwiftUI

/// The design tokens for ABV, in one place so a restyle is a diff here rather than a sweep through
/// every view (the same reason `ValueChips` exists).
///
/// **The idea the look comes from.** This app gets used standing at a bar, in dim light, to decide
/// what is worth buying. It is a measuring instrument, so it borrows from the things it measures:
/// bottle glass and poured liquid. But it is a casual app for a night out, not a sommelier's tool,
/// so the type is **rounded**, not the serif of a spirits label — friendly and a bit chunky, closer
/// to a chalkboard than a wine list. Nothing in here is decorative: the palette is glass and liquid,
/// and the one loud element is the value figure, because that number is the entire product.
///
/// The darks are deliberately **green-tinted**, not neutral charcoal. That follows from the accent
/// green the project already picked "to read as glass", and it keeps the dark theme from looking
/// like every other dark theme.
enum Theme {

    // MARK: - Palette

    /// Page background. Cool pale green-grey, not cream — this is glassware, not parchment.
    static let canvas = adaptive(light: 0xEEF2EF, dark: 0x0D1411)
    /// A raised surface: a drink row, a sheet, a card.
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x16211C)
    /// Bottle green. The brand colour and every primary action.
    static let glass = adaptive(light: 0x145C3F, dark: 0x4FB584)
    /// Reserved for one meaning only: **this number is an estimate** (§11). Nothing else wears it,
    /// so an amber chip anywhere in the app means the same thing. It also stays clear of the rank
    /// medals, which is why the value figure is green rather than amber.
    static let amber = adaptive(light: 0xA86A12, dark: 0xE3AC4E)
    static let ink = adaptive(light: 0x0F1713, dark: 0xE9F0EA)
    static let inkMuted = adaptive(light: 0x55665D, dark: 0x8FA398)

    /// A hairline that reads as an edge, not a shadow.
    static var hairline: Color { inkMuted.opacity(0.22) }
    /// The wash behind a chip. One value, so chips never drift apart.
    static func wash(_ color: Color) -> Color { color.opacity(0.13) }

    // MARK: - Type
    //
    // Two families, clearly distinct. SF Rounded is the voice: wordmark, titles, and every measured
    // number — soft, confident, unfussy. SF Pro is the machinery: body copy and chips, where rounded
    // would get mushy at small sizes. Rounded numerals in particular are what make the value figure
    // feel like a score rather than a spreadsheet cell.

    static func display(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
    static var wordmark: Font { display(44, .heavy) }
    static var title: Font { display(26) }
    static var figure: Font { display(34, .heavy) }
    static var figureSmall: Font { display(22) }
    /// Button and card titles.
    static var action: Font { display(19, .semibold) }

    static var body: Font { .system(size: 17) }
    static var callout: Font { .system(size: 16) }
    static var label: Font { .system(size: 13, weight: .medium) }
    static var micro: Font { .system(size: 11, weight: .semibold) }

    // MARK: - Metrics

    static let radius: CGFloat = 14
    static let radiusSmall: CGFloat = 9
    /// A 4pt rhythm. Named so a view asks for a step rather than inventing a number.
    enum Space {
        static let hair: CGFloat = 4
        static let tight: CGFloat = 8
        static let snug: CGFloat = 12
        static let base: CGFloat = 16
        static let loose: CGFloat = 24
        static let wide: CGFloat = 36
    }

    // MARK: - Plumbing

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

// MARK: - Brand

/// The wordmark. `ABV` is an acronym, so it is set in caps on purpose; the expansion underneath is
/// the product promise in sentence case, and it is what makes the pun land rather than just reading
/// as a chemistry abbreviation.
struct Wordmark: View {
    var size: CGFloat = 40
    var showsExpansion = true

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ABV")
                .font(Theme.display(size, .heavy))
                .tracking(-size * 0.015)
                .foregroundStyle(Theme.ink)
            if showsExpansion {
                Text("A better value")
                    .font(.system(size: max(12, size * 0.3), weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.glass)
            }
        }
    }
}

// MARK: - The value figure

/// The number the whole app exists to produce, with a **pour line** under it filled to this drink's
/// share of the best value on the list.
///
/// The bar is information, not ornament: the list is ranked, so the eye wants to know *by how much*
/// first place wins. A podium of medals says the order and hides the margin.
struct ValueFigure: View {
    /// Standard drinks per dollar (or whatever the active metric measures).
    let value: Double
    /// The best value on the current list, for the fill fraction. Pass `value` when alone.
    let best: Double
    let unit: String

    private var fraction: Double {
        guard best > 0, value.isFinite else { return 0 }
        return min(1, max(0.04, value / best))
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: Theme.Space.hair) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.2f", value))
                    .font(Theme.figure)
                    .monospacedDigit()
                    .foregroundStyle(Theme.glass)
                Text(unit)
                    .font(Theme.micro)
                    .foregroundStyle(Theme.inkMuted)
            }
            PourLine(fraction: fraction)
                .frame(width: 78, height: 3)
        }
    }
}

/// A hairline channel with the filled portion in amber. Reads as liquid to a level.
struct PourLine: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.inkMuted.opacity(0.18))
                Capsule().fill(Theme.glass).frame(width: geo.size.width * fraction)
            }
        }
    }
}

// MARK: - Buttons

/// The one primary action on a screen.
struct PourButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.action)
            .foregroundStyle(Theme.canvas)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(Theme.glass, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

/// A full-height home-screen action: big icon, title, and one line saying what it does.
///
/// These are sized to **divide the screen** rather than sit in a stack at the top, so the home
/// screen is a set of doors rather than a paragraph with buttons under it. The primary one is
/// filled; the rest are outlined, which is what keeps four large cards from reading as four equal
/// choices.
struct ActionCardStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.action)
            .foregroundStyle(isPrimary ? Theme.canvas : Theme.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.base)
            .background {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .fill(isPrimary ? Theme.glass : Theme.surface)
            }
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 1)
                }
            }
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}

/// The label inside an `ActionCardStyle` button.
struct ActionCardLabel: View {
    let title: String
    let detail: String
    let systemImage: String
    var isPrimary = false

    var body: some View {
        HStack(spacing: Theme.Space.base) {
            Image(systemName: systemImage)
                .font(.system(size: 26, weight: .medium))
                .frame(width: 34)
                .foregroundStyle(isPrimary ? Theme.canvas : Theme.glass)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.system(size: 13))
                    .foregroundStyle(isPrimary ? Theme.canvas.opacity(0.85) : Theme.inkMuted)
            }
        }
    }
}

// MARK: - Notices

/// A quiet, non-alarming banner. Used for the thin-read warning (C) and any other "read this before
/// you trust the list" message. Amber, not red: nothing has failed, the answer is just softer than
/// usual.
struct Notice: View {
    let text: String
    var systemImage: String = "drop.triangle"

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.tight) {
            Image(systemName: systemImage)
                .font(.system(size: 13))
                .foregroundStyle(Theme.amber)
            Text(text)
                .font(Theme.label)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Theme.Space.snug)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.wash(Theme.amber),
                    in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}


// MARK: - Chip row

/// Lays chips out left to right and **wraps** to a new line when the next one doesn't fit.
///
/// A plain `HStack` spreads its available width across its children, so a chip row that overflows
/// gets *compressed* rather than wrapped, and SwiftUI truncates whichever child it likes: on a row
/// reading `4.2% ABV` the honesty badge came out as "estimat…", while the same row at `5% ABV` fit
/// and looked fine. That is the worst possible thing to truncate — the badge is the §11 promise —
/// and it failed intermittently on the width of a decimal point.
///
/// Wrapping is the honest fix. Chips keep their natural size and the row grows taller instead of
/// eating its own text, so nothing depends on how many characters the ABV happens to have.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var lineWidth: CGFloat = 0, lineHeight: CGFloat = 0
        var total = CGSize.zero

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if lineWidth > 0, lineWidth + spacing + size.width > maxWidth {
                total.width = max(total.width, lineWidth)
                total.height += lineHeight + lineSpacing
                lineWidth = size.width
                lineHeight = size.height
            } else {
                lineWidth += lineWidth > 0 ? spacing + size.width : size.width
                lineHeight = max(lineHeight, size.height)
            }
        }
        total.width = max(total.width, lineWidth)
        total.height += lineHeight
        return total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
