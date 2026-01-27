import SwiftUI

struct SettingsView: View {
    @State private var autoReconnect = true
    @State private var preferControlEscape = true
    @State private var useHaptics = false

    var body: some View {
        Form {
            Section("Connection") {
                Toggle("Auto-reconnect", isOn: $autoReconnect)
                Toggle("Haptics", isOn: $useHaptics)
            }

            Section("Input") {
                Toggle("Ctrl/Esc helpers", isOn: $preferControlEscape)
            }

            Section("About") {
                NavigationLink("Licenses") {
                    LicensesView()
                }
            }
        }
        .navigationTitle("Settings")
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
