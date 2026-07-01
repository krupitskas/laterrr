import SwiftData
import SwiftUI

struct ReviewTabView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settingsStore: SettingsStore

    @StateObject private var photoReviewController = PhotoLibraryReviewController()
    @State private var isPhotoReviewPickerPresented = false

    var body: some View {
        ZStack {
            LaterrrBackground()

            VStack(spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 20) {
                    ZStack {
                        PlaceNetworkAnimation()

                        MicroText("Scanning your photo library", size: 9, kerning: 1.5, color: LaterrrPalette.inkSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(LaterrrPalette.canvas)
                            .overlay {
                                Rectangle()
                                    .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                            }
                            .offset(y: 8)
                            .frame(maxHeight: .infinity, alignment: .bottom)
                            .padding(.bottom, 14)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(LaterrrPalette.canvas)
                    .overlay {
                        Rectangle()
                            .strokeBorder(LaterrrPalette.ink, lineWidth: 1)
                    }

                    Text("laterrr scans recent photos with location data, looks for place text, and builds a review deck before anything is saved.")
                        .font(LaterrrTypography.body(.subheadline))
                        .foregroundStyle(LaterrrPalette.inkSecondary)

                    Button {
                        isPhotoReviewPickerPresented = true
                    } label: {
                        Text("Start review")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.inkPrimary)
                    .disabled(photoReviewController.isPreparing)
                }
                .padding(20)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog(
            "Review your recent photos",
            isPresented: $isPhotoReviewPickerPresented,
            titleVisibility: .visible
        ) {
            Button("Last 7 days") {
                startPhotoReview(dayWindow: 7)
            }

            Button("Last 14 days") {
                startPhotoReview(dayWindow: 14)
            }

            Button("Last 30 days") {
                startPhotoReview(dayWindow: 30)
            }

            Button("Last 90 days") {
                startPhotoReview(dayWindow: 90)
            }

            Button("Last 180 days") {
                startPhotoReview(dayWindow: 180)
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("laterrr will scan recent photos with location data, look for place text, and build a review deck before anything is saved.")
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { photoReviewController.isPresentingReview },
                set: { if !$0 { photoReviewController.dismissReview() } }
            )
        ) {
            PhotoLibraryReviewView(
                controller: photoReviewController,
                skipAction: {
                    photoReviewController.skipCurrent()
                },
                saveAction: {
                    photoReviewController.saveCurrent(modelContext: modelContext)
                }
            )
        }
        .overlay {
            if photoReviewController.isPreparing && !photoReviewController.isPresentingReview {
                LaterrrPalette.canvas.opacity(0.8)
                    .ignoresSafeArea()
                    .overlay {
                        InkCard(alignment: .center) {
                            InkSpinner(size: 36)

                            Text("Reviewing recent place photos")
                                .font(LaterrrTypography.display(26))
                                .foregroundStyle(LaterrrPalette.ink)
                                .multilineTextAlignment(.center)

                            InkProgressBar(value: photoReviewController.progressFraction)

                            Text(photoReviewController.progressSummary)
                                .font(LaterrrTypography.body(.subheadline))
                                .foregroundStyle(LaterrrPalette.inkSecondary)
                                .multilineTextAlignment(.center)

                            Button {
                                photoReviewController.dismissReview()
                            } label: {
                                Text("Cancel")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.inkOutline)
                        }
                        .frame(maxWidth: 340)
                        .padding(24)
                    }
            }
        }
        .alert(
            "Photos Review",
            isPresented: Binding(
                get: { photoReviewController.alertMessage != nil },
                set: { if !$0 { photoReviewController.dismissAlert() } }
            )
        ) {
            Button("OK", role: .cancel) {
                photoReviewController.dismissAlert()
            }
        } message: {
            Text(photoReviewController.alertMessage ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroText("Photos review", color: LaterrrPalette.inkSecondary)

            Text("Review.")
                .font(LaterrrTypography.display(44))
                .foregroundStyle(LaterrrPalette.ink)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            HairlineDivider()
        }
    }

    private func startPhotoReview(dayWindow: Int) {
        photoReviewController.startReview(
            dayWindow: dayWindow,
            enableLookAroundVerification: settingsStore.enableLookAroundVerification
        )
    }
}

// MARK: - Network graph animation
// A drifting constellation of ink nodes joined by hairlines whenever they come close —
// places connecting into a map. Pure ink on canvas, no color.

private struct PlaceNetworkAnimation: View {
    private struct Node {
        let baseX: CGFloat
        let baseY: CGFloat
        let amplitudeX: CGFloat
        let amplitudeY: CGFloat
        let speedX: Double
        let speedY: Double
        let phaseX: Double
        let phaseY: Double
        let radius: CGFloat
        let isAnchor: Bool
    }

    private let nodes: [Node] = Self.makeNodes(count: 26)

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let inset: CGFloat = 14

                let points: [CGPoint] = nodes.map { node in
                    let x = node.baseX + node.amplitudeX * CGFloat(sin(time * node.speedX + node.phaseX))
                    let y = node.baseY + node.amplitudeY * CGFloat(cos(time * node.speedY + node.phaseY))
                    return CGPoint(
                        x: inset + x * (size.width - inset * 2),
                        y: inset + y * (size.height - inset * 2)
                    )
                }

                let threshold = min(size.width, size.height) * 0.34

                for firstIndex in points.indices {
                    for secondIndex in points.indices where secondIndex > firstIndex {
                        let dx = points[firstIndex].x - points[secondIndex].x
                        let dy = points[firstIndex].y - points[secondIndex].y
                        let distance = sqrt(dx * dx + dy * dy)

                        guard distance < threshold else { continue }

                        let strength = 1 - distance / threshold
                        var path = Path()
                        path.move(to: points[firstIndex])
                        path.addLine(to: points[secondIndex])
                        context.stroke(
                            path,
                            with: .color(LaterrrPalette.ink.opacity(Double(strength) * 0.4)),
                            lineWidth: 1
                        )
                    }
                }

                for (index, point) in points.enumerated() {
                    let node = nodes[index]
                    let rect = CGRect(
                        x: point.x - node.radius,
                        y: point.y - node.radius,
                        width: node.radius * 2,
                        height: node.radius * 2
                    )

                    if node.isAnchor {
                        context.fill(Path(ellipseIn: rect), with: .color(LaterrrPalette.canvas))
                        context.stroke(
                            Path(ellipseIn: rect),
                            with: .color(LaterrrPalette.ink),
                            lineWidth: 1.5
                        )

                        let dotRadius = node.radius * 0.4
                        let dotRect = CGRect(
                            x: point.x - dotRadius,
                            y: point.y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        )
                        context.fill(Path(ellipseIn: dotRect), with: .color(LaterrrPalette.ink))
                    } else {
                        context.fill(Path(ellipseIn: rect), with: .color(LaterrrPalette.ink))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func makeNodes(count: Int) -> [Node] {
        var generator = SplitMix64(seed: 0x1A7E44)

        return (0 ..< count).map { index in
            Node(
                baseX: CGFloat.random(in: 0.05 ... 0.95, using: &generator),
                baseY: CGFloat.random(in: 0.05 ... 0.95, using: &generator),
                amplitudeX: CGFloat.random(in: 0.03 ... 0.10, using: &generator),
                amplitudeY: CGFloat.random(in: 0.03 ... 0.10, using: &generator),
                speedX: Double.random(in: 0.12 ... 0.4, using: &generator),
                speedY: Double.random(in: 0.12 ... 0.4, using: &generator),
                phaseX: Double.random(in: 0 ... .pi * 2, using: &generator),
                phaseY: Double.random(in: 0 ... .pi * 2, using: &generator),
                radius: index % 7 == 0
                    ? CGFloat.random(in: 5.5 ... 7, using: &generator)
                    : CGFloat.random(in: 1.6 ... 2.6, using: &generator),
                isAnchor: index % 7 == 0
            )
        }
    }
}

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var result = state
        result = (result ^ (result >> 30)) &* 0xBF58476D1CE4E5B9
        result = (result ^ (result >> 27)) &* 0x94D049BB133111EB
        return result ^ (result >> 31)
    }
}
