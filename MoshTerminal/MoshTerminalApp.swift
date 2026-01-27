import SwiftUI

@main
struct MoshTerminalApp: App {
    @StateObject private var environment = AppEnvironment()
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .environmentObject(settings)
                .tint(AppTheme.tintColor)
                .preferredColorScheme(settings.themeMode.preferredColorScheme)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            NavigationStack {
                HostsListView(
                    hostRepository: environment.dependencies.hostRepository,
                    keyStore: environment.dependencies.keyStore,
                    connectionManager: environment.dependencies.connectionManager
                )
            }
            .tabItem {
                Label("Hosts", systemImage: "server.rack")
            }

            NavigationStack {
                ContentUnavailableView(
                    "Select a Host",
                    systemImage: "server.rack",
                    description: Text("Open a host from the Hosts tab.")
                )
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
