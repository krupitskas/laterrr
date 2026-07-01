import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            LaterrrBackground()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        section(title: "Sync") {
                            settingRow(
                                title: "Save to iCloud",
                                subtitle: "Coming soon. laterrr will surface a clearer manual iCloud sync control here.",
                                isOn: .constant(false),
                                isDisabled: true
                            )

                            HairlineDivider(color: LaterrrPalette.ink.opacity(0.2))

                            settingRow(
                                title: "Sync with Bump",
                                subtitle: "Stub for a future export and sync bridge with Bump.",
                                isOn: .constant(false),
                                isDisabled: true
                            )
                        }

                        section(title: "Capture") {
                            settingRow(
                                title: "Keep a photo snapshot with each saved place",
                                subtitle: "Helpful when you want the storefront image to stay attached to your list in iCloud.",
                                isOn: $settingsStore.keepPhotoSnapshot
                            )

                            HairlineDivider(color: LaterrrPalette.ink.opacity(0.2))

                            settingRow(
                                title: "Improve matches with Look Around",
                                subtitle: "When Apple street-level imagery exists, laterrr compares it to your photo and shows the visual preview in the ranking.",
                                isOn: $settingsStore.enableLookAroundVerification
                            )
                        }
                    }
                    .padding(20)
                }
                .scrollIndicators(.hidden)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroText("Preferences", color: LaterrrPalette.inkSecondary)

            Text("Settings.")
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

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MicroText(title, color: LaterrrPalette.inkSecondary)
                .padding(.bottom, 10)

            HairlineDivider()

            content()

            HairlineDivider()
        }
    }

    private func settingRow(
        title: String,
        subtitle: String,
        isOn: Binding<Bool>,
        isDisabled: Bool = false
    ) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(LaterrrTypography.headline(.subheadline))
                    .foregroundStyle(LaterrrPalette.ink)

                Text(subtitle)
                    .font(LaterrrTypography.body(.footnote))
                    .foregroundStyle(LaterrrPalette.inkSecondary)
            }
        }
        .tint(LaterrrPalette.ink)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .padding(.vertical, 14)
    }
}
