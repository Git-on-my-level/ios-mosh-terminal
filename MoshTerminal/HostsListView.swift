import SwiftUI

private struct Host: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let address: String
}

struct HostsListView: View {
    private let sampleHosts: [Host] = [
        Host(name: "Home Lab", address: "mosh.example.net"),
        Host(name: "Workstation", address: "192.168.1.42"),
        Host(name: "VPS", address: "vps.example.com"),
    ]

    var body: some View {
        List(sampleHosts) { host in
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(host.name)
                        .font(.headline)
                    Text(host.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                NavigationLink("Connect", value: host)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Hosts")
        .navigationDestination(for: Host.self) { host in
            TerminalView(host: host.name)
        }
    }
}

#Preview {
    NavigationStack {
        HostsListView()
    }
}
