import Prediction
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        Form {
            Section {
                ThemePickerRow(selection: $settings.themeMode)

                Stepper(value: $settings.fontSize, in: 10...24, step: 1) {
                    HStack {
                        AppRowLabel("Font Size", systemImage: "textformat.size")
                        Spacer()
                        Text("\(Int(settings.fontSize))")
                            .foregroundStyle(colors.secondaryText)
                        Text("Aa")
                            .font(.system(size: settings.fontSize + 2, weight: .semibold, design: .rounded))
                            .foregroundStyle(colors.primaryText)
                    }
                }
            } header: {
                SectionHeader("Appearance")
            }

            Section {
                Toggle(isOn: $settings.keepAwake) {
                    AppRowLabel("Keep Awake", systemImage: "sun.max")
                }
                Toggle(isOn: predictionsEnabledBinding) {
                    AppRowLabel("Predictions", systemImage: "bolt")
                }
            } header: {
                SectionHeader("Session")
            }

            Section {
                NavigationLink {
                    KeyManagementView(
                        hostRepository: environment.dependencies.hostRepository,
                        keyStore: environment.dependencies.keyStore
                    )
                } label: {
                    AppRowLabel("Manage Keys", systemImage: "key")
                }
                NavigationLink {
                    TrustedHostKeysView(repository: environment.dependencies.trustedHostKeyRepository)
                } label: {
                    AppRowLabel("Trusted Host Keys", systemImage: "checkmark.shield")
                }
            } header: {
                SectionHeader("Keys")
            }

            Section {
                NavigationLink {
                    AboutView()
                } label: {
                    AppRowLabel("About", systemImage: "info.circle")
                }
            } header: {
                SectionHeader("About")
            }

            Section {
                NavigationLink {
                    TipJarView()
                } label: {
                    AppRowLabel("Tip Jar", systemImage: "heart")
                }
            } header: {
                SectionHeader("Support Development")
            } footer: {
                Text("Optional tip. No additional features are unlocked.")
            }

#if DEBUG
            Section {
                Toggle(isOn: $settings.debugOverlayEnabled) {
                    AppRowLabel("Show Debug Overlay", systemImage: "ladybug")
                }
                Toggle(isOn: $settings.debugLoggingEnabled) {
                    AppRowLabel("Enable Debug Logging", systemImage: "doc.text.magnifyingglass")
                }
                Toggle(isOn: $settings.debugPredictionEnabled) {
                    AppRowLabel("Enable Predictions", systemImage: "bolt")
                }
            } header: {
                SectionHeader("Debug")
            }
#endif
        }
        .navigationTitle("Settings")
        .appScreenBackground()
    }

    private var predictionsEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.predictionDisplayPreference != .off },
            set: { isOn in
                settings.predictionDisplayPreference = isOn ? .always : .off
            }
        )
    }
}

private struct ThemePickerRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppSettings.ThemeMode

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        VStack(alignment: .leading, spacing: 8) {
            AppRowLabel("Theme", systemImage: "paintbrush")
            HStack(spacing: 8) {
                themeChip(title: "Light", systemImage: "sun.max", isActive: selection == .light, colors: colors) {
                    selection = .light
                }
                themeChip(title: "Dark", systemImage: "moon", isActive: selection == .dark, colors: colors) {
                    selection = .dark
                }
                themeChip(title: "System", systemImage: "circle.lefthalf.filled", isActive: selection == .system, colors: colors) {
                    selection = .system
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
    }

    private func themeChip(
        title: String,
        systemImage: String,
        isActive: Bool,
        colors: AppTheme.Colors,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(AppTheme.typography.caption)
            }
            .foregroundStyle(isActive ? colors.primaryText : colors.secondaryText)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isActive ? colors.surfaceElevated : colors.surface)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isActive ? colors.accent : colors.divider, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AppSettings())
    .environmentObject(AppEnvironment())
    .environmentObject(TipJarStore())
}
