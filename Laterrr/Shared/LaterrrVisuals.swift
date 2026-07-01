import CoreText
import SwiftUI
import UIKit

// MARK: - Palette
// Monochrome editorial system: pure ink on pure canvas.
// Light mode is canonical; dark mode is a clean inversion of the same two tones.

enum LaterrrPalette {
    static let uiInk = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .white : .black
    }

    static let uiCanvas = UIColor { traits in
        traits.userInterfaceStyle == .dark ? .black : .white
    }

    static let ink = Color(uiInk)
    static let canvas = Color(uiCanvas)
    static let inkSecondary = ink.opacity(0.55)
    static let inkTertiary = ink.opacity(0.45)
}

// MARK: - Fonts

enum LaterrrFonts {
    static let serif = "InstrumentSerif-Regular"
    static let serifItalic = "InstrumentSerif-Italic"

    static func registerBundledFonts() {
        for fontName in [serif, serifItalic] {
            guard
                UIFont(name: fontName, size: 12) == nil,
                let fontURL = Bundle.main.url(forResource: fontName, withExtension: "ttf")
            else { continue }

            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }
}

// MARK: - Typography
// Serif is only for display headings, place names, and short italic accents.
// Everything functional is sans; small labels are uppercase letterspaced micro type.

enum LaterrrTypography {
    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        let fontName = italic ? LaterrrFonts.serifItalic : LaterrrFonts.serif

        if UIFont(name: fontName, size: size) != nil {
            return .custom(fontName, size: size, relativeTo: .largeTitle)
        }

        let fallback = Font.system(size: size, weight: .regular, design: .serif)
        return italic ? fallback.italic() : fallback
    }

    static func accent(_ size: CGFloat = 16) -> Font {
        display(size, italic: true)
    }

    static func headline(_ textStyle: Font.TextStyle = .headline) -> Font {
        .system(textStyle, design: .default, weight: .semibold)
    }

    static func body(_ textStyle: Font.TextStyle = .body) -> Font {
        .system(textStyle, design: .default, weight: .regular)
    }

    static func caption(_ textStyle: Font.TextStyle = .caption) -> Font {
        .system(textStyle, design: .default, weight: .medium)
    }

    static func micro(_ size: CGFloat = 10) -> Font {
        .system(size: size, weight: .semibold)
    }

    static func uiDisplay(_ size: CGFloat) -> UIFont {
        UIFont(name: LaterrrFonts.serif, size: size) ?? systemSerifUIFont(size: size)
    }

    static func uiHeadline(_ textStyle: UIFont.TextStyle = .headline) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        return uiDisplay(size)
    }

    private static func systemSerifUIFont(size: CGFloat) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: .regular)
        guard let serifDescriptor = baseFont.fontDescriptor.withDesign(.serif) else {
            return baseFont
        }

        return UIFont(descriptor: serifDescriptor, size: size)
    }
}

// MARK: - Chrome

enum LaterrrChrome {
    @MainActor
    static func configureNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = LaterrrPalette.uiCanvas
        appearance.shadowColor = LaterrrPalette.uiInk
        appearance.titleTextAttributes = [
            .font: LaterrrTypography.uiHeadline(),
            .foregroundColor: LaterrrPalette.uiInk
        ]
        appearance.largeTitleTextAttributes = [
            .font: LaterrrTypography.uiDisplay(36),
            .foregroundColor: LaterrrPalette.uiInk
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = LaterrrPalette.uiInk
    }
}

// MARK: - Background

struct LaterrrBackground: View {
    var body: some View {
        LaterrrPalette.canvas
            .ignoresSafeArea()
    }
}

// MARK: - Micro label
// Uppercase, letterspaced grotesque label used for section heads, metadata, chips.

struct MicroText: View {
    let text: String
    var size: CGFloat = 10
    var kerning: CGFloat = 2
    var color: Color = LaterrrPalette.ink

    @ScaledMetric(relativeTo: .caption2) private var scale: CGFloat = 1

    init(_ text: String, size: CGFloat = 10, kerning: CGFloat = 2, color: Color = LaterrrPalette.ink) {
        self.text = text
        self.size = size
        self.kerning = kerning
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(LaterrrTypography.micro(size * scale))
            .kerning(kerning)
            .foregroundStyle(color)
    }
}

// MARK: - Hairlines

struct HairlineDivider: View {
    var color: Color = LaterrrPalette.ink

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: 1)
    }
}

struct InkKeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            MicroText(key, color: LaterrrPalette.inkSecondary)
                .frame(width: 92, alignment: .leading)

            Text(value)
                .font(LaterrrTypography.body(.subheadline))
                .foregroundStyle(LaterrrPalette.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }
}

// MARK: - Card

struct InkCard<Content: View>: View {
    let alignment: HorizontalAlignment
    let content: Content

    init(alignment: HorizontalAlignment = .leading, @ViewBuilder content: () -> Content) {
        self.alignment = alignment
        self.content = content()
    }

    var body: some View {
        VStack(alignment: alignment, spacing: 12) {
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .background(LaterrrPalette.canvas)
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
    }
}

// MARK: - Chips

struct ConfidencePill: View {
    let score: Double
    var caption: String = "MATCH"

    var body: some View {
        let clampedScore = min(max(score, 0), 1)

        MicroText("\(Int((clampedScore * 100).rounded()))% \(caption)", size: 9, kerning: 1.5)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LaterrrPalette.canvas)
            .overlay {
                Rectangle()
                    .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
            }
    }
}

struct LaterrrTag: View {
    let title: String

    var body: some View {
        MicroText(title, size: 9, kerning: 1.5)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(LaterrrPalette.canvas)
            .overlay {
                Rectangle()
                    .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
            }
    }
}

// MARK: - Buttons
// Primary: ink fill, canvas micro label. Secondary: hairline outline.
// Press state inverts fill and text; no color shift.

struct InkButtonStyle: ButtonStyle {
    var prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let isFilled = prominent != configuration.isPressed

        configuration.label
            .font(LaterrrTypography.micro(11))
            .kerning(2)
            .textCase(.uppercase)
            .lineLimit(1)
            .foregroundStyle(isFilled ? LaterrrPalette.canvas : LaterrrPalette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(isFilled ? LaterrrPalette.ink : LaterrrPalette.canvas)
            .overlay {
                Rectangle()
                    .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
            }
            .contentShape(Rectangle())
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var inkPrimary: InkButtonStyle { InkButtonStyle(prominent: true) }
    static var inkOutline: InkButtonStyle { InkButtonStyle(prominent: false) }
}

// MARK: - Crosshatch
// Fine 45° hatch used wherever the old design used gray fills.

struct CrosshatchPattern: View {
    var lineColor: Color = LaterrrPalette.ink
    var lineOpacity: Double = 0.12
    var spacing: CGFloat = 7

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var offset = -size.height

            while offset < size.width {
                path.move(to: CGPoint(x: offset, y: 0))
                path.addLine(to: CGPoint(x: offset + size.height, y: size.height))
                offset += spacing
            }

            context.stroke(path, with: .color(lineColor.opacity(lineOpacity)), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct CrosshatchPlaceholder: View {
    var caption: String?

    var body: some View {
        ZStack {
            LaterrrPalette.canvas
            CrosshatchPattern()

            if let caption {
                MicroText(caption, color: LaterrrPalette.inkSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(LaterrrPalette.canvas)
                    .overlay {
                        Rectangle()
                            .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                    }
            }
        }
        .overlay {
            Rectangle()
                .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
        }
    }
}

// MARK: - Loader
// The single loading style: a spinning ink circle-outline carrying one ink dot.

struct InkSpinner: View {
    var size: CGFloat = 28
    var color: Color = LaterrrPalette.ink

    @State private var isSpinning = false

    var body: some View {
        ZStack(alignment: .top) {
            Circle()
                .strokeBorder(color, lineWidth: 1.5)

            Circle()
                .fill(color)
                .frame(width: size * 0.2, height: size * 0.2)
                .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size)
        .rotationEffect(.degrees(isSpinning ? 360 : 0))
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                isSpinning = true
            }
        }
        .accessibilityLabel("Loading")
    }
}

struct InkProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(LaterrrPalette.ink.opacity(0.15))
                    .frame(height: 1)
                    .frame(maxHeight: .infinity)

                Rectangle()
                    .fill(LaterrrPalette.ink)
                    .frame(width: geometry.size.width * min(max(value, 0), 1), height: 3)
            }
        }
        .frame(height: 3)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(value, 0), 1) * 100).rounded())) percent")
    }
}

struct LaterrrLoadingView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            InkSpinner(size: 40)

            Text(title)
                .font(LaterrrTypography.display(28))
                .foregroundStyle(LaterrrPalette.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(LaterrrTypography.body(.subheadline))
                .foregroundStyle(LaterrrPalette.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(28)
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        InkCard(alignment: .center) {
            CrosshatchPlaceholder()
                .frame(width: 72, height: 72)

            Text(title)
                .font(LaterrrTypography.display(26))
                .foregroundStyle(LaterrrPalette.ink)
                .multilineTextAlignment(.center)

            Text(message)
                .font(LaterrrTypography.body(.subheadline))
                .foregroundStyle(LaterrrPalette.inkSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

// MARK: - Tab bar
// Flat editorial bar: hairline top rule, uppercase micro labels, active tab underlined.

struct EditorialTabBar<Selection: Hashable>: View {
    let items: [(title: String, value: Selection)]
    @Binding var selection: Selection

    var body: some View {
        VStack(spacing: 0) {
            HairlineDivider()

            HStack(spacing: 0) {
                ForEach(items.indices, id: \.self) { index in
                    let item = items[index]
                    let isActive = selection == item.value

                    Button {
                        selection = item.value
                    } label: {
                        VStack(spacing: 6) {
                            MicroText(
                                item.title,
                                size: 9,
                                kerning: 1.5,
                                color: isActive ? LaterrrPalette.ink : LaterrrPalette.inkTertiary
                            )

                            Rectangle()
                                .fill(isActive ? LaterrrPalette.ink : Color.clear)
                                .frame(width: 26, height: 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(isActive ? [.isSelected] : [])
                }
            }
        }
        .background(LaterrrPalette.canvas)
    }
}
