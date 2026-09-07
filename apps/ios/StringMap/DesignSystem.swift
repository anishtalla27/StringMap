import SwiftUI

// StringMap's visual language. The interface is an aged-nitro cream chassis in
// light and a dark tobacco one in dark; the instrument itself is always a
// rosewood faceplate mounted into it — nickel fret wire, a bone nut, bronze
// strings — the way an amplifier is actually built. That inversion, not the
// hue, is what keeps the screen from reading flat.
//
// One accent runs the interface: fiesta red. Lake blue and surf green never
// touch a control; they carry meaning inside data only — the note coming next
// on the board, the cost bars in the trace, a capo. Amber appears once, as the
// sunburst on a score's artwork.

// MARK: - Palette

extension Color {
    /// Resolves to a different value per appearance. Both values are authored
    /// deliberately; neither is derived from the other by lightening.
    static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Fixed across appearances. Used only for the instrument, which is a dark
    /// object in a light room and a dark object in a dark one.
    static func fixed(_ rgb: UInt32) -> Color {
        Color(uiColor: UIColor(rgb: rgb))
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

enum Palette {
    // The one interface accent: fiesta red, a vintage instrument colour rather
    // than a saturated UI red.
    static let brand = Color.adaptive(light: 0xC43A25, dark: 0xE0765C)
    static let brandDeep = Color.adaptive(light: 0x96240F, dark: 0xC4543A)

    // Surface ramp. Light is aged nitro cream; dark is warm tobacco, never a
    // neutral graphite and never pure black.
    static let surfaceBase = Color.adaptive(light: 0xF3EDE0, dark: 0x1A1410)
    static let surfaceBaseEdge = Color.adaptive(light: 0xEFE7D6, dark: 0x141009)
    static let surfaceRaised = Color.adaptive(light: 0xFFFCF4, dark: 0x241C16)
    static let surfaceInset = Color.adaptive(light: 0xE6DCC8, dark: 0x120E0B)

    // Hairlines and shadows are tinted to the surface hue, never pure black.
    static let hairline = Color.adaptive(light: 0xD5C8B0, dark: 0x3B2E24)
    static let shadowTint = Color.adaptive(light: 0x5A4632, dark: 0x000000)

    // Instrument materials. Fixed in both appearances — the neck is the same
    // piece of wood whichever room you are in.
    static let plateHighlight = Color.fixed(0x33261D)
    static let plateEdge = Color.fixed(0x160F0C)
    static let board = Color.fixed(0x33261E)
    static let boardEdge = Color.fixed(0x241A15)
    static let fretWire = Color.fixed(0xCFCCC4)
    static let stringLine = Color.fixed(0xC9B98F)
    static let inlay = Color.fixed(0xE8DFCB)
    static let bone = Color.fixed(0xEDE3CD)
    /// Type set directly on the faceplate, which has its own contrast rules.
    static let onPlate = Color.fixed(0xA89880)
    static let onPlateDim = Color.fixed(0x8A7B67)

    // Semantic states. The same colour always means the same thing: red is the
    // note sounding now, blue is the note coming next, and green is something
    // settled — a fingering you pinned, a capo you set, a check that passed.
    static let positionActive = Color.adaptive(light: 0xC43A25, dark: 0xE0765C)
    static let positionUpcoming = Color.adaptive(light: 0x1B7FA6, dark: 0x5FA8C8)
    static let positionLocked = Color.adaptive(light: 0x2C8B63, dark: 0x6FC49E)
    static let positionRejected = Color.adaptive(light: 0x8D8270, dark: 0x8A7F6E)
    /// Baseline, non-directional cost in the trace bars.
    static let neutralData = Color.adaptive(light: 0x9A8D78, dark: 0x8A7F6E)
    /// Energy and recoverable trouble, never a control. Warnings take amber
    /// rather than a red, because the accent is already a red and a warning
    /// that looks like a button is worse than no colour at all.
    static let amber = Color.adaptive(light: 0xB8770F, dark: 0xE3B457)

    // Score paper. Sheet music is paper; in dark it becomes the darkest warm
    // paper that still reads as a page. `ScoreTheme` mirrors this into alphaTab
    // so the notation is part of the app rather than a white hole in it.
    static let scorePaper = Color.adaptive(light: 0xFFFDF7, dark: 0x1E1812)
}

// MARK: - Score finishes

/// Scores are told apart the way guitars are: by finish, not by rotating one
/// gradient around the colour wheel.
enum ScoreFinish: CaseIterable {
    case sunburst, butterscotch, fiesta, lake, surf, cherry, ebony

    var stops: [Color] {
        switch self {
        case .sunburst: [.fixed(0xE0A63F), .fixed(0xB06326), .fixed(0x4A2A14)]
        case .butterscotch: [.fixed(0xEDCB77), .fixed(0xD2A03C), .fixed(0x8A5C15)]
        case .fiesta: [.fixed(0xE0765C), .fixed(0xC43A25), .fixed(0x6E1A0B)]
        case .lake: [.fixed(0x8FC6DC), .fixed(0x3E93B8), .fixed(0x134F6C)]
        case .surf: [.fixed(0x9BD4B7), .fixed(0x3F9E78), .fixed(0x175440)]
        case .cherry: [.fixed(0xC96874), .fixed(0xA32F3E), .fixed(0x54121C)]
        case .ebony: [.fixed(0x5A5049), .fixed(0x2C2622), .fixed(0x100D0B)]
        }
    }

    /// Butterscotch and sunburst are too close to tell apart at list size, and
    /// a fiesta-bodied score would read as an interface element rather than as
    /// artwork, so neither is in the rotation.
    private static let rotation: [ScoreFinish] = [.sunburst, .lake, .surf, .cherry, .ebony]

    /// Stable per title, so a score keeps the same finish for its whole life.
    ///
    /// FNV-1a, bucketed on the high half. The obvious djb2 loop was tried first
    /// and is unusable here: its low bits track the last few characters, so a
    /// library of similarly-named studies came out almost entirely one colour.
    static func forSeed(_ seed: String) -> ScoreFinish {
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in seed.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3
        }
        return rotation[Int((hash >> 32) % UInt64(rotation.count))]
    }
}

// MARK: - Spacing

enum Space {
    static let hair: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    /// Long-form content stops growing past a comfortable measure on iPad.
    static let readingWidth: CGFloat = 680
}

enum Radius {
    static let shell: CGFloat = 20
    static let core: CGFloat = 14
    static let chip: CGFloat = 10

    /// Concentric curves: an inner radius must shrink by exactly the inset, or
    /// the two curves visibly disagree.
    static func nested(_ outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(4, outer - inset)
    }
}

// MARK: - Motion

enum Motion {
    /// Spring physics rather than a linear ramp — markers travel with mass.
    static let travel = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let settle = Animation.spring(response: 0.30, dampingFraction: 0.85)
    static let reveal = Animation.spring(response: 0.50, dampingFraction: 0.90)
}

/// Collapses an animation to nothing when the reader has asked for reduced
/// motion, so every animated surface can opt in with one modifier.
struct ReduceMotionAware: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: AnyHashable

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    func motion(_ animation: Animation, value: some Hashable) -> some View {
        modifier(ReduceMotionAware(animation: animation, value: AnyHashable(value)))
    }
}

// MARK: - Typography

extension View {
    /// Structural micro-label: small caps, tracked out, never shouting.
    func eyebrow() -> some View {
        self
            .font(.caption2.smallCaps())
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }

    /// Numbers that change in place must not re-flow the layout around them.
    func stableNumber(_ style: Font = .subheadline) -> some View {
        self.font(style.monospacedDigit())
    }
}

// MARK: - Metadata

/// Facts about a score read as one typographic line — "10 notes · 104 BPM ·
/// Standard tuning" — rather than as a row of pills. Pills fragment a sentence
/// into badges and cost more space than the words they hold.
struct MetaLine: View {
    let parts: [String]
    var font: Font = .subheadline
    var tint: Color?

    init(_ parts: [String], font: Font = .subheadline, tint: Color? = nil) {
        self.parts = parts.filter { !$0.isEmpty }
        self.font = font
        self.tint = tint
    }

    var body: some View {
        Text(parts.joined(separator: " · "))
            .font(font.monospacedDigit())
            .foregroundStyle(tint ?? Color.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(parts.joined(separator: ", "))
    }
}

/// One column of an aligned numeric row. Comparing arrangements is comparing
/// numbers, so they line up in columns instead of scattering into chips.
struct NumberColumn: View {
    let label: String
    let value: String
    /// The rule belongs to the gap between two columns, so it is drawn on the
    /// leading edge of the column that follows it — drawn trailing, it ends up
    /// flush against the next label instead of centred in the gap.
    var showsLeadingRule = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
        }
        .padding(.leading, showsLeadingRule ? Space.m : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .leading) {
            if showsLeadingRule {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 0.5)
                    .padding(.vertical, 1)
            }
        }
    }
}

// MARK: - Surfaces

/// The nested "machined hardware" container: an outer shell holding an inner
/// core, with concentric radii. Used for anything that should read as a
/// physical component rather than a floating rectangle.
struct Bezel<Content: View>: View {
    var outerRadius: CGFloat = Radius.shell
    var inset: CGFloat = Space.xs
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background(Palette.surfaceRaised, in: innerShape)
            .overlay {
                innerShape.strokeBorder(Palette.hairline, lineWidth: 0.5)
            }
            .padding(inset)
            .background(Palette.surfaceInset.opacity(0.7), in: outerShape)
            .overlay {
                outerShape.strokeBorder(Palette.hairline.opacity(0.7), lineWidth: 0.5)
            }
            .shadow(color: Palette.shadowTint.opacity(0.10), radius: 6, y: 3)
    }

    private var outerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: outerRadius, style: .continuous)
    }

    private var innerShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.nested(outerRadius, inset: inset), style: .continuous)
    }
}

/// A single-layer card for content that does not need the hardware treatment.
struct Panel<Content: View>: View {
    var radius: CGFloat = Radius.core
    var padded = true
    var isSelected = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padded ? Space.l : 0)
            .background(Palette.surfaceRaised, in: shape)
            .overlay {
                shape.strokeBorder(
                    isSelected ? Palette.brand : Palette.hairline,
                    lineWidth: isSelected ? 1.5 : 0.5
                )
            }
            .shadow(color: Palette.shadowTint.opacity(0.08), radius: 4, y: 2)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

/// A dark rosewood strip carrying type, the way a tuning is stamped on a
/// headstock. Used wherever the app states what the instrument itself is.
struct InstrumentPlate<Content: View>: View {
    var radius: CGFloat = Radius.chip
    var showsNut = true
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: Space.m) {
            if showsNut {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Palette.bone)
                    .frame(width: 3)
            }
            content
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, Space.m - 1)
        .background {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Palette.plateHighlight, Palette.boardEdge],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Palette.plateEdge, lineWidth: 1)
        }
    }
}

/// Decorative rule with a light source — not a plain Divider.
struct GradientRule: View {
    var tint: Color = Palette.brand

    var body: some View {
        LinearGradient(
            colors: [.clear, tint.opacity(0.24), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
    }
}

/// Section heading with an eyebrow above it, used instead of a bare
/// `Section("Title")` so headings carry hierarchy.
struct SectionHeading: View {
    let eyebrow: String
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(eyebrow).eyebrow()
            Text(title)
                .font(.title3.weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The room the instrument sits in: a slow vertical wash rather than a flat
/// fill, and no coloured corner glows — the accent is spent on the fretboard.
struct AmbientBackground: View {
    var body: some View {
        LinearGradient(
            colors: [Palette.surfaceBase, Palette.surfaceBaseEdge],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}
