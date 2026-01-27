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
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            NavigationStack {
                HostsListView(
                    hostRepository: environment.dependencies.hostRepository,
                    keyStore: environment.dependencies.keyStore,
                    moshBootstrapper: environment.dependencies.moshBootstrapper,
                    moshEngineFactory: environment.dependencies.moshEngineFactory
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
