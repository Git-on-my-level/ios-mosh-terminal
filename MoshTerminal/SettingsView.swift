import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $settings.themeMode) {
                    ForEach(AppSettings.ThemeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Stepper(value: $settings.fontSize, in: 10...24, step: 1) {
                    HStack {
                        Text("Font Size")
                        Spacer()
                        Text("\(Int(settings.fontSize))")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Session") {
                Toggle("Keep Awake", isOn: $settings.keepAwake)
            }

            Section("Keys") {
                NavigationLink("Manage Keys") {
                    KeyManagementView()
                }
                NavigationLink("Trusted Host Keys") {
                    TrustedHostKeysView(repository: environment.dependencies.trustedHostKeyRepository)
                }
            }

            Section("About") {
                NavigationLink("Licenses") {
                    LicensesView()
                }
            }

#if DEBUG
            Section("Debug") {
                Toggle("Show Debug Overlay", isOn: $settings.debugOverlayEnabled)
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
