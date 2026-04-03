import SwiftUI
import UIKit

enum LaterrrPalette {
    static let canvas = Color(red: 0.96, green: 0.97, blue: 0.995)
    static let canvasHighlight = Color(red: 0.84, green: 0.88, blue: 1.0)
    static let canvasAccent = Color(red: 0.94, green: 0.87, blue: 0.99)
    static let accent = Color(red: 0.47, green: 0.40, blue: 0.83)
    static let accentBright = Color(red: 0.78, green: 0.88, blue: 1.0)
    static let accentSoft = Color(red: 0.89, green: 0.86, blue: 0.99)
    static let textPrimary = Color(red: 0.05, green: 0.06, blue: 0.11)
    static let textSecondary = Color(red: 0.18, green: 0.20, blue: 0.29)
    static let cardStroke = Color.white.opacity(0.96)
    static let shadow = Color(red: 0.16, green: 0.14, blue: 0.30).opacity(0.12)
}

enum LaterrrTypography {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func headline(_ textStyle: UIFont.TextStyle = .headline) -> Font {
        let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        return .system(size: size, weight: .semibold, design: .serif)
    }

    static func body(_ textStyle: UIFont.TextStyle = .body) -> Font {
        let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        return .system(size: size, weight: .regular, design: .serif)
    }

    static func caption(_ textStyle: UIFont.TextStyle = .caption1) -> Font {
        let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        return .system(size: size, weight: .medium, design: .serif)
    }

    static func uiDisplay(_ size: CGFloat) -> UIFont {
        systemSerifUIFont(size: size, weight: .semibold)
    }

    static func uiHeadline(_ textStyle: UIFont.TextStyle = .headline) -> UIFont {
        let size = UIFont.preferredFont(forTextStyle: textStyle).pointSize
        return systemSerifUIFont(size: size, weight: .semibold)
    }

    private static func systemSerifUIFont(size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let baseFont = UIFont.systemFont(ofSize: size, weight: weight)
        guard let serifDescriptor = baseFont.fontDescriptor.withDesign(.serif) else {
            return baseFont
        }

        return UIFont(descriptor: serifDescriptor, size: size)
    }
}

enum LaterrrChrome {
    @MainActor
    static func configureNavigationAppearance() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = .clear
        appearance.titleTextAttributes = [
            .font: LaterrrTypography.uiHeadline(),
            .foregroundColor: UIColor(LaterrrPalette.textPrimary)
        ]
        appearance.largeTitleTextAttributes = [
            .font: LaterrrTypography.uiDisplay(36),
            .foregroundColor: UIColor(LaterrrPalette.textPrimary)
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.tintColor = UIColor(LaterrrPalette.accent)
    }
}

struct LaterrrBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.white,
                    LaterrrPalette.canvas,
                    Color(red: 0.93, green: 0.95, blue: 1.0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            LaterrrPalette.accentBright.opacity(0.85),
                            LaterrrPalette.canvasHighlight.opacity(0.25)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 360, height: 360)
                .blur(radius: 70)
                .offset(x: 150, y: -240)

            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            LaterrrPalette.canvasAccent.opacity(0.92),
                            Color.white.opacity(0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 420, height: 420)
                .blur(radius: 84)
                .offset(x: -130, y: 280)

            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .strokeBorder(Color.white.opacity(0.42), lineWidth: 1)
                .padding(10)

            Rectangle()
                .fill(Color.white.opacity(0.08))
        }
        .ignoresSafeArea()
    }
}

struct GlassCard<Content: View>: View {
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
        .glassEffect(
            Glass.regular.tint(Color.white.opacity(0.74)),
            in: RoundedRectangle(cornerRadius: 30, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.96),
                            LaterrrPalette.accentBright.opacity(0.88),
                            LaterrrPalette.accent.opacity(0.30)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.15
                )
        }
        .shadow(color: LaterrrPalette.shadow, radius: 22, y: 12)
    }
}

struct ConfidencePill: View {
    let score: Double

    var body: some View {
        let clampedScore = min(max(score, 0), 1)
        let tint = LinearGradient(
            colors: [
                Color.white.opacity(0.92),
                LaterrrPalette.accentSoft.opacity(0.94),
                LaterrrPalette.accentBright.opacity(0.70)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )

        Text("\(Int((clampedScore * 100).rounded()))% match")
            .font(LaterrrTypography.caption())
            .foregroundStyle(LaterrrPalette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(tint)
            )
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.90), lineWidth: 1)
            }
            .shadow(color: LaterrrPalette.shadow.opacity(0.65), radius: 16, y: 8)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        GlassCard(alignment: .center) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(LaterrrPalette.accent)

            Text(title)
                .font(LaterrrTypography.display(24))
                .foregroundStyle(LaterrrPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(LaterrrTypography.body())
                .foregroundStyle(LaterrrPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct LaterrrTag: View {
    let title: String

    var body: some View {
        Text(title)
            .font(LaterrrTypography.caption(.caption2))
            .foregroundStyle(LaterrrPalette.textPrimary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.94),
                                LaterrrPalette.accentSoft.opacity(0.72)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.84), lineWidth: 1)
            }
    }
}

struct LaterrrBrandStar: View {
    let size: CGFloat
    var isSpinning = false

    @State private var rotation: Double = 0

    var body: some View {
        Image("BrandStar")
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
            .rotationEffect(.degrees(rotation))
            .shadow(color: LaterrrPalette.accent.opacity(0.18), radius: 18, y: 8)
            .onAppear {
                guard isSpinning else { return }
                rotation = 360
            }
            .animation(
                isSpinning ? .linear(duration: 1.35).repeatForever(autoreverses: false) : .default,
                value: rotation
            )
    }
}

struct LaterrrLoadingView: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            LaterrrBrandStar(size: 132, isSpinning: true)

            Text(title)
                .font(LaterrrTypography.display(28))
                .foregroundStyle(LaterrrPalette.textPrimary)

            Text(message)
                .font(LaterrrTypography.body())
                .foregroundStyle(LaterrrPalette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .padding(28)
    }
}
