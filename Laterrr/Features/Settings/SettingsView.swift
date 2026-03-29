import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            LaterrrBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GlassCard {
                        Text("Default map")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Picker("Maps Provider", selection: $settingsStore.preferredMapsProvider) {
                            ForEach(MapProvider.allCases) { provider in
                                Text(provider.title).tag(provider)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text(settingsStore.preferredMapsProvider.summary)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(LaterrrPalette.textSecondary)
                    }

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

                            Toggle(isOn: $settingsStore.autoOpenMapAfterSave) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Open the map provider right after saving")
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(LaterrrPalette.textPrimary)

                                    Text("Useful when you want directions or the full place card immediately.")
                                        .font(.system(.subheadline, design: .rounded))
                                        .foregroundStyle(LaterrrPalette.textSecondary)
                                }
                            }
                            .tint(LaterrrPalette.accent)
                        }
                    }

                    GlassCard {
                        Text("Matching engine")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Text("Laterrr stays local: on-device OCR plus deterministic nearby-place matching.")
                            .font(.system(.body, design: .rounded))
                            .foregroundStyle(LaterrrPalette.textPrimary)

                        Text(VenueMatcher.matchingSummary())
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(LaterrrPalette.textSecondary)

                        Text("This keeps the core flow consistent in Europe and avoids depending on region-limited intelligence features.")
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(LaterrrPalette.textSecondary)
                    }
                }
                .padding(20)
            }
        }
        .navigationTitle("Settings")
    }
}
