import SwiftUI

@main
struct MoshTerminalApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .tint(AppTheme.tintColor)
        }
    }
}

private struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                HostsListView()
            }
            .tabItem {
                Label("Hosts", systemImage: "server.rack")
            }

            NavigationStack {
                TerminalView(host: "Preview")
            }
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
