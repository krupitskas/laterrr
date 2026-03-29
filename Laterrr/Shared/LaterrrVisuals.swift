import SwiftUI

enum LaterrrPalette {
    static let canvas = Color(red: 0.95, green: 0.97, blue: 0.96)
    static let canvasHighlight = Color(red: 0.84, green: 0.92, blue: 0.90)
    static let canvasAccent = Color(red: 0.86, green: 0.91, blue: 0.97)
    static let accent = Color(red: 0.15, green: 0.53, blue: 0.49)
    static let accentSoft = Color(red: 0.66, green: 0.84, blue: 0.80)
    static let textPrimary = Color(red: 0.13, green: 0.17, blue: 0.19)
    static let textSecondary = Color(red: 0.34, green: 0.40, blue: 0.42)
    static let cardStroke = Color.white.opacity(0.78)
    static let shadow = Color.black.opacity(0.08)
}

struct LaterrrBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white, LaterrrPalette.canvas, Color.white],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(LaterrrPalette.canvasHighlight.opacity(0.95))
                .frame(width: 300, height: 300)
                .blur(radius: 40)
                .offset(x: 135, y: -240)

            Circle()
                .fill(LaterrrPalette.canvasAccent.opacity(0.95))
                .frame(width: 380, height: 380)
                .blur(radius: 70)
                .offset(x: -120, y: 260)

            Rectangle()
                .fill(Color.white.opacity(0.14))
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
            Glass.regular.tint(Color.white.opacity(0.56)),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(LaterrrPalette.cardStroke, lineWidth: 1)
        }
        .shadow(color: LaterrrPalette.shadow, radius: 22, y: 12)
    }
}

struct ConfidencePill: View {
    let score: Double

    var body: some View {
        let clampedScore = min(max(score, 0), 1)
        let tint = Color(
            red: 0.72 - (0.10 * clampedScore),
            green: 0.78 + (0.10 * clampedScore),
            blue: 0.68 - (0.05 * clampedScore)
        )

        Text("\(Int((clampedScore * 100).rounded()))% match")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(LaterrrPalette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glassEffect(
                Glass.regular.tint(tint.opacity(0.84)),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(Color.white.opacity(0.82), lineWidth: 1)
            }
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
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(LaterrrPalette.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundStyle(LaterrrPalette.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}
