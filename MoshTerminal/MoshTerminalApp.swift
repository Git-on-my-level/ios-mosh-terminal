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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        TabView {
            NavigationStack {
                HostsListView(
                    hostRepository: environment.dependencies.hostRepository,
                    keyStore: environment.dependencies.keyStore,
                    connectionManager: environment.dependencies.connectionManager
                )
            }
            .toolbarBackground(colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tabItem {
                Label("Hosts", systemImage: "server.rack")
            }

            NavigationStack {
                SettingsView()
            }
            .toolbarBackground(colors.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .toolbarBackground(colors.surface, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
