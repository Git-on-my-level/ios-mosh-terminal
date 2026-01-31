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
        List {
            if viewModel.keys.isEmpty {
                ContentUnavailableView(
                    "No Trusted Keys",
                    systemImage: "lock.shield",
                    description: Text("Saved host fingerprints appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.keys, id: \.self) { key in
                    TrustedHostKeyRow(key: key)
                }
                .onDelete { offsets in
                    Task { await viewModel.deleteKeys(at: offsets) }
                }
            }
        }
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
    }
}

private struct TrustedHostKeyRow: View {
    let key: TrustedHostKey

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(key.hostname):\(key.port)")
                .font(.headline)
            Text(key.fingerprint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fontDesign(.monospaced)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        TrustedHostKeysView(repository: TrustedHostKeyRepository(store: JSONStore()))
    }
}
