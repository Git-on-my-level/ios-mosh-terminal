import SwiftUI

@MainActor
final class HostsListViewModel: ObservableObject {
    @Published var hosts: [HostProfile] = []
    @Published var alertMessage: String?

    private let hostRepository: any HostRepositoryProtocol

    init(hostRepository: any HostRepositoryProtocol) {
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
    @State private var pendingHostDeletion: [HostProfile] = []
    @State private var isShowingDeleteConfirmation = false

    private let hostRepository: any HostRepositoryProtocol
    private let keyStore: any PrivateKeyManaging
    @ObservedObject private var connectionManager: ConnectionManager

    init(
        hostRepository: any HostRepositoryProtocol,
        keyStore: any PrivateKeyManaging,
        connectionManager: ConnectionManager
    ) {
        self.hostRepository = hostRepository
        self.keyStore = keyStore
        _connectionManager = ObservedObject(wrappedValue: connectionManager)
        _viewModel = StateObject(wrappedValue: HostsListViewModel(hostRepository: hostRepository))
    }

    var body: some View {
        let metrics = AppTheme.metrics
        List {
            if viewModel.hosts.isEmpty {
                EmptyStateActionView(
                    title: "No Hosts",
                    systemImage: "server.rack",
                    description: "Add a host to get started.",
                    actionTitle: "Add Host",
                    action: { editorContext = HostEditorContext(mode: .create) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
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
                        CardRow(isActive: connectionManager.state(for: host.id).isActive) {
                            HostRowView(
                                host: host,
                                connectionState: connectionManager.state(for: host.id)
                            )
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: metrics.rowSpacing / 2, leading: 16, bottom: metrics.rowSpacing / 2, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            requestDelete(host)
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
                            requestDelete(host)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    requestDelete(at: offsets)
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(metrics.rowSpacing)
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
        .alert(deleteAlertTitle, isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingHostDeletion = []
            }
            Button(deleteConfirmationButtonTitle, role: .destructive) {
                Task { await confirmHostDeletion() }
            }
        } message: {
            Text(deleteAlertMessage)
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
        .appScreenBackground()
    }

    private var deleteAlertTitle: String {
        pendingHostDeletion.count == 1 ? "Delete Host?" : "Delete Hosts?"
    }

    private var deleteConfirmationButtonTitle: String {
        pendingHostDeletion.count == 1 ? "Delete Host" : "Delete \(pendingHostDeletion.count) Hosts"
    }

    private var deleteAlertMessage: String {
        guard pendingHostDeletion.count == 1, let host = pendingHostDeletion.first else {
            return "This will permanently remove the selected hosts."
        }
        return "Delete \"\(host.resolvedDisplayName)\"? This cannot be undone."
    }

    private func requestDelete(_ host: HostProfile) {
        pendingHostDeletion = [host]
        isShowingDeleteConfirmation = true
    }

    private func requestDelete(at offsets: IndexSet) {
        let hosts = offsets.map { viewModel.hosts[$0] }
        guard !hosts.isEmpty else {
            return
        }
        pendingHostDeletion = hosts
        isShowingDeleteConfirmation = true
    }

    private func confirmHostDeletion() async {
        let hostsToDelete = pendingHostDeletion
        pendingHostDeletion = []
        guard !hostsToDelete.isEmpty else {
            return
        }
        await deleteHosts(hostsToDelete)
    }

    private func deleteHosts(_ hosts: [HostProfile]) async {
        for host in hosts {
            await connectionManager.disconnect(hostId: host.id, clearSession: true)
            await viewModel.deleteHost(id: host.id)
        }
        await viewModel.loadHosts()
    }
}

private struct HostRowView: View {
    let host: HostProfile
    let connectionState: ConnectionManager.State
    @Environment(\.colorScheme) private var colorScheme

    private var lastConnectedText: String? {
        guard let date = host.lastConnectedAt else {
            return nil
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: date, relativeTo: Date())
        return "Last connected \(relative)"
    }

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(host.resolvedDisplayName)
                    .font(AppTheme.typography.headline)
                    .foregroundStyle(colors.primaryText)
                Spacer(minLength: 8)
                StatusBadge(state: connectionState)
            }
            Text("\(host.username)@\(host.hostname)")
                .font(AppTheme.typography.captionMonospaced)
                .foregroundStyle(colors.secondaryText)
            if let lastConnectedText {
                Text(lastConnectedText)
                    .font(AppTheme.typography.caption)
                    .foregroundStyle(colors.secondaryText)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: connectionState)
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
        let previewDeps = AppEnvironment.makePreviewDependencies()
        HostsListView(
            hostRepository: previewDeps.hostRepository,
            keyStore: previewDeps.keyStore,
            connectionManager: previewDeps.connectionManager
        )
    }
}
