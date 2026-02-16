import SwiftUI

@MainActor
final class TrustedHostKeysViewModel: ObservableObject {
    @Published var keys: [TrustedHostKey] = []
    @Published var alertMessage: String?

    private let repository: any TrustedHostKeyManaging

    init(repository: any TrustedHostKeyManaging) {
        self.repository = repository
    }

    func loadKeys() async {
        do {
            keys = try await repository.all()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func deleteKeys(at offsets: IndexSet) async {
        let toDelete = offsets.map { keys[$0] }
        for key in toDelete {
            do {
                try await repository.delete(hostname: key.hostname, port: key.port, fingerprint: key.fingerprint)
            } catch {
                alertMessage = error.localizedDescription
                break
            }
        }
        await loadKeys()
    }
}

struct TrustedHostKeysView: View {
    @StateObject private var viewModel: TrustedHostKeysViewModel
    @State private var pendingDeletion: TrustedHostKey?
    @State private var isShowingDeleteConfirmation = false

    init(repository: any TrustedHostKeyManaging) {
        _viewModel = StateObject(wrappedValue: TrustedHostKeysViewModel(repository: repository))
    }

    var body: some View {
        let metrics = AppTheme.metrics
        List {
            if viewModel.keys.isEmpty {
                ContentUnavailableView(
                    "No Trusted Keys",
                    systemImage: "lock.shield",
                    description: Text("Saved host fingerprints appear here.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.keys, id: \.self) { key in
                    CardRow {
                        TrustedHostKeyRow(key: key)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: metrics.rowSpacing / 2, leading: 16, bottom: metrics.rowSpacing / 2, trailing: 16))
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            requestDelete(key)
                        }
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            requestDelete(key)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(metrics.rowSpacing)
        .navigationTitle("Trusted Host Keys")
        .alert("Delete Trusted Host Key?", isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingDeletion = nil
            }
            Button("Delete", role: .destructive) {
                Task { await confirmDelete() }
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .alert(
            "Trusted Host Keys",
            isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { _ in viewModel.alertMessage = nil })
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .task {
            await viewModel.loadKeys()
        }
        .appScreenBackground()
    }

    private var deleteAlertMessage: String {
        guard let pendingDeletion else {
            return "This will remove the selected trusted host key."
        }
        return "Delete \(pendingDeletion.hostname):\(pendingDeletion.port)? This cannot be undone."
    }

    private func requestDelete(_ key: TrustedHostKey) {
        pendingDeletion = key
        isShowingDeleteConfirmation = true
    }

    private func confirmDelete() async {
        guard let key = pendingDeletion else {
            return
        }
        pendingDeletion = nil
        guard let index = viewModel.keys.firstIndex(of: key) else {
            return
        }
        await viewModel.deleteKeys(at: IndexSet(integer: index))
    }
}

private struct TrustedHostKeyRow: View {
    let key: TrustedHostKey
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        VStack(alignment: .leading, spacing: 6) {
            Text("\(key.hostname):\(key.port)")
                .font(AppTheme.typography.headline)
                .foregroundStyle(colors.primaryText)
            Text(key.fingerprint)
                .font(AppTheme.typography.captionMonospaced)
                .foregroundStyle(colors.secondaryText)
        }
    }
}

#Preview {
    NavigationStack {
        let previewDeps = AppEnvironment.makePreviewDependencies()
        TrustedHostKeysView(repository: previewDeps.trustedHostKeyRepository)
    }
}
