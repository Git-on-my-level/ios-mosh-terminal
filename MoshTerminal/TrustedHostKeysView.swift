import SwiftUI

@MainActor
final class TrustedHostKeysViewModel: ObservableObject {
    @Published var keys: [TrustedHostKey] = []
    @Published var alertMessage: String?

    private let repository: TrustedHostKeyRepository

    init(repository: TrustedHostKeyRepository) {
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

    init(repository: TrustedHostKeyRepository) {
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
                }
                .onDelete { offsets in
                    Task { await viewModel.deleteKeys(at: offsets) }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(metrics.rowSpacing)
        .navigationTitle("Trusted Host Keys")
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
        TrustedHostKeysView(repository: TrustedHostKeyRepository(store: JSONStore()))
    }
}
