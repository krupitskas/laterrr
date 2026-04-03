import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            LaterrrBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: 14) {
                            Toggle(isOn: $settingsStore.keepPhotoSnapshot) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Keep a photo snapshot with each saved place")
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(LaterrrPalette.textPrimary)

                                    Text("Helpful when you want the storefront image to stay attached to your list in iCloud.")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(LaterrrPalette.textSecondary)
                                }
                            }
                            .tint(LaterrrPalette.accent)

                            Toggle(isOn: .constant(false)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Save to iCloud")
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(LaterrrPalette.textPrimary)

                                    Text("Stub for a future manual sync toggle. The current data container setup still handles storage automatically.")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(LaterrrPalette.textSecondary)
                                }
                            }
                            .tint(LaterrrPalette.accent)
                            .disabled(true)
                            .opacity(0.58)

                            Toggle(isOn: $settingsStore.enableLookAroundVerification) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Improve matches with Look Around")
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(LaterrrPalette.textPrimary)

                                    Text("When Apple street-level imagery exists, Laterrr compares it to your photo and shows the visual preview in the ranking.")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(LaterrrPalette.textSecondary)
                                }
                            }
                            .tint(LaterrrPalette.accent)

                        }
                    }
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Settings")
    }
}
