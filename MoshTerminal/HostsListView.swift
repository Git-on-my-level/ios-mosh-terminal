import SwiftUI

@MainActor
final class HostsListViewModel: ObservableObject {
    @Published var hosts: [HostProfile] = []
    @Published var alertMessage: String?

    private let hostRepository: HostRepository

    init(hostRepository: HostRepository) {
        self.hostRepository = hostRepository
    }

    func loadHosts() {
        do {
            let loaded = try hostRepository.all()
            hosts = loaded.sorted(by: HostsListViewModel.sortHosts)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func deleteHosts(at offsets: IndexSet) {
        let ids = offsets.map { hosts[$0].id }
        for id in ids {
            deleteHost(id: id)
        }
        loadHosts()
    }

    func deleteHost(id: UUID) {
        do {
            try hostRepository.delete(id: id)
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

    init(hostRepository: HostRepository, keyStore: KeychainPrivateKeyStore) {
        self.hostRepository = hostRepository
        self.keyStore = keyStore
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
                        TerminalView(host: host.resolvedDisplayName)
                    } label: {
                        HostRowView(host: host)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            viewModel.deleteHost(id: host.id)
                            viewModel.loadHosts()
                        }
                        Button("Edit") {
                            editorContext = HostEditorContext(mode: .edit(host))
                        }
                        .tint(.blue)
                    }
                }
                .onDelete(perform: viewModel.deleteHosts)
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
                    viewModel.loadHosts()
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
        .onAppear {
            viewModel.loadHosts()
        }
    }
}

private struct HostRowView: View {
    let host: HostProfile

    private var lastConnectedText: String? {
        guard let date = host.lastConnectedAt else {
            return nil
        }
        return "Last connected \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(host.resolvedDisplayName)
                .font(.headline)
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
        HostsListView(hostRepository: HostRepository(store: JSONStore()), keyStore: KeychainPrivateKeyStore())
    }
}
