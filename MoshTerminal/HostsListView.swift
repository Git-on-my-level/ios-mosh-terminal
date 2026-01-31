import SwiftUI

@MainActor
final class HostsListViewModel: ObservableObject {
    @Published var hosts: [HostProfile] = []
    @Published var alertMessage: String?

    private let hostRepository: HostRepository

    init(hostRepository: HostRepository) {
        self.hostRepository = hostRepository
    }

    func loadHosts() async {
        do {
            let loaded = try await hostRepository.all()
            hosts = loaded.sorted(by: HostsListViewModel.sortHosts)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func deleteHosts(at offsets: IndexSet) async {
        let ids = offsets.map { hosts[$0].id }
        for id in ids {
            await deleteHost(id: id)
        }
        await loadHosts()
    }

    func deleteHost(id: UUID) async {
        do {
            try await hostRepository.delete(id: id)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private static func sortHosts(lhs: HostProfile, rhs: HostProfile) -> Bool {
        let lhsName = lhs.resolvedDisplayName.lowercased()
        let rhsName = rhs.resolvedDisplayName.lowercased()
        if lhsName != rhsName {
            return lhsName < rhsName
        }
        if lhs.hostname != rhs.hostname {
            return lhs.hostname < rhs.hostname
        }
        return lhs.username < rhs.username
    }
}

struct HostsListView: View {
    @StateObject private var viewModel: HostsListViewModel
    @State private var editorContext: HostEditorContext?

    private let hostRepository: HostRepository
    private let keyStore: KeychainPrivateKeyStore
    @ObservedObject private var connectionManager: ConnectionManager

    init(
        hostRepository: HostRepository,
        keyStore: KeychainPrivateKeyStore,
        connectionManager: ConnectionManager
    ) {
        self.hostRepository = hostRepository
        self.keyStore = keyStore
        _connectionManager = ObservedObject(wrappedValue: connectionManager)
        _viewModel = StateObject(wrappedValue: HostsListViewModel(hostRepository: hostRepository))
    }

    var body: some View {
        List {
            if viewModel.hosts.isEmpty {
                ContentUnavailableView("No Hosts", systemImage: "server.rack", description: Text("Add a host to get started."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.hosts) { host in
                    NavigationLink {
                        TerminalView(
                            host: host,
                            dependencies: TerminalSessionDependencies(
                                connectionManager: connectionManager
                            )
                        )
                    } label: {
                        HostRowView(
                            host: host,
                            connectionState: connectionManager.activeHostId == host.id ? connectionManager.state : .idle
                        )
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            Task {
                                if connectionManager.activeHostId == host.id {
                                    await connectionManager.disconnect(clearSession: true)
                                }
                                await viewModel.deleteHost(id: host.id)
                                await viewModel.loadHosts()
                            }
                        }
                        Button("Edit") {
                            editorContext = HostEditorContext(mode: .edit(host))
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            editorContext = HostEditorContext(mode: .edit(host))
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task {
                                if connectionManager.activeHostId == host.id {
                                    await connectionManager.disconnect(clearSession: true)
                                }
                                await viewModel.deleteHost(id: host.id)
                                await viewModel.loadHosts()
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    Task {
                        for offset in offsets {
                            let hostId = viewModel.hosts[offset].id
                            if connectionManager.activeHostId == hostId {
                                await connectionManager.disconnect(clearSession: true)
                            }
                        }
                        await viewModel.deleteHosts(at: offsets)
                    }
                }
            }
        }
        .navigationTitle("Hosts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editorContext = HostEditorContext(mode: .create)
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Host")
            }
        }
        .sheet(item: $editorContext) { context in
            NavigationStack {
                HostEditorView(
                    host: context.host,
                    hostRepository: hostRepository,
                    keyStore: keyStore
                ) { _ in
                    Task { await viewModel.loadHosts() }
                }
            }
        }
        .alert(
            "Hosts",
            isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { _ in viewModel.alertMessage = nil })
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .task {
            await viewModel.loadHosts()
        }
    }
}

private struct HostRowView: View {
    let host: HostProfile
    let connectionState: ConnectionManager.State

    private var lastConnectedText: String? {
        guard let date = host.lastConnectedAt else {
            return nil
        }
        return "Last connected \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(host.resolvedDisplayName)
                    .font(.headline)
                Text(connectionState.shortStatusText)
                    .font(.caption2)
                    .foregroundStyle(statusColor(for: connectionState))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor(for: connectionState).opacity(0.15))
                    .clipShape(Capsule())
            }
            Text("\(host.username)@\(host.hostname)")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let lastConnectedText {
                Text(lastConnectedText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(for state: ConnectionManager.State) -> Color {
        switch state {
        case .connected:
            return .green
        case .bootstrappingSSH, .connectingUDP, .reconnecting:
            return .orange
        case .failed, .disconnected:
            return .red
        case .idle:
            return .secondary
        }
    }
}

private struct HostEditorContext: Identifiable {
    enum Mode {
        case create
        case edit(HostProfile)
    }

    let id = UUID()
    let mode: Mode

    var host: HostProfile? {
        switch mode {
        case .create:
            return nil
        case .edit(let host):
            return host
        }
    }
}

#Preview {
    NavigationStack {
        let store = JSONStore()
        let trustedHostKeyRepository = TrustedHostKeyRepository(store: store)
        let sshClientFactory = DefaultSSHClientFactory.make(repository: trustedHostKeyRepository)
        let keyStore = KeychainPrivateKeyStore()
        let moshBootstrapper = MoshBootstrapper(sshClientFactory: sshClientFactory)
        let appLifecycleService = AppLifecycleService()
        let networkPathService = NetworkPathService()
        let hostRepository = HostRepository(store: store)
        let connectionManager = ConnectionManager(
            keyStore: keyStore,
            hostRepository: hostRepository,
            moshBootstrapper: moshBootstrapper,
            moshEngineFactory: { LoopbackMoshEngine() },
            appLifecycleService: appLifecycleService,
            networkPathService: networkPathService
        )
        HostsListView(
            hostRepository: hostRepository,
            keyStore: keyStore,
            connectionManager: connectionManager
        )
    }
}
