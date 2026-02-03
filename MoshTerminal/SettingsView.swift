import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Form {
            Section("Appearance") {
                Picker(selection: $settings.themeMode) {
                    ForEach(AppSettings.ThemeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                } label: {
                    Label("Theme", systemImage: "paintbrush")
                }
                Stepper(value: $settings.fontSize, in: 10...24, step: 1) {
                    HStack {
                        Label("Font Size", systemImage: "textformat.size")
                        Spacer()
                        Text("\(Int(settings.fontSize))")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Session") {
                Toggle(isOn: $settings.keepAwake) {
                    Label("Keep Awake", systemImage: "sun.max")
                }
                Picker(selection: $settings.predictionDisplayPreference) {
                    ForEach(PredictionDisplayPreference.allCases) { preference in
                        Text(preference.displayName).tag(preference)
                    }
                } label: {
                    Label("Predictions", systemImage: "bolt")
                }
            }

            Section("Keys") {
                NavigationLink {
                    KeyManagementView(
                        hostRepository: environment.dependencies.hostRepository,
                        keyStore: environment.dependencies.keyStore
                    )
                } label: {
                    Label("Manage Keys", systemImage: "key")
                }
                NavigationLink {
                    TrustedHostKeysView(repository: environment.dependencies.trustedHostKeyRepository)
                } label: {
                    Label("Trusted Host Keys", systemImage: "checkmark.shield")
                }
            }

            Section("About") {
                NavigationLink {
                    AboutView()
                } label: {
                    Label("About", systemImage: "info.circle")
                }
            }

#if DEBUG
            Section("Debug") {
                Toggle(isOn: $settings.debugOverlayEnabled) {
                    Label("Show Debug Overlay", systemImage: "ladybug")
                }
                Toggle(isOn: $settings.debugLoggingEnabled) {
                    Label("Enable Debug Logging", systemImage: "doc.text.magnifyingglass")
                }
                NavigationLink {
                    DebugLogView()
                } label: {
                    Label("Debug Logs", systemImage: "doc.text")
                }
                Toggle(isOn: $settings.debugPredictionEnabled) {
                    Label("Enable Predictions", systemImage: "bolt")
                }
            }
#endif
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(AppSettings())
    .environmentObject(AppEnvironment())
}
