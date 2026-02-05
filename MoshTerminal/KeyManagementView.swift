import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class KeyManagementViewModel: ObservableObject {
    @Published var keys: [StoredPrivateKeyMetadata] = []
    @Published var alertMessage: String?

    private let store: KeychainPrivateKeyStore
    private let hostRepository: HostRepository

    init(
        store: KeychainPrivateKeyStore = KeychainPrivateKeyStore(),
        hostRepository: HostRepository = HostRepository(store: JSONStore())
    ) {
        self.store = store
        self.hostRepository = hostRepository
    }

    func loadKeys() {
        do {
            keys = try store.listKeys()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func importKeyFromFile(data: Data, label: String?) {
        do {
            let normalizedData = try normalizePrivateKeyData(data)
            guard let text = String(data: normalizedData, encoding: .utf8) else {
                alertMessage = "Unable to read key as text."
                return
            }
            importKey(text: text, data: normalizedData, label: label)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func importKeyFromPaste(text: String, label: String?) {
        do {
            let data = Data(text.utf8)
            let normalizedData = try normalizePrivateKeyData(data)
            guard let normalizedText = String(data: normalizedData, encoding: .utf8) else {
                alertMessage = "Unable to read key as text."
                return
            }
            importKey(text: normalizedText, data: normalizedData, label: label)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func deleteKeys(at offsets: IndexSet) async {
        let ids = offsets.map { keys[$0].id }
        guard !ids.isEmpty else {
            return
        }
        do {
            let hosts = try await hostRepository.all()
            let referencedHosts = hosts.filter { ids.contains($0.keyRefId) }
            if !referencedHosts.isEmpty {
                alertMessage = makeDeletionBlockedMessage(hosts: referencedHosts, keyCount: ids.count)
                return
            }
        } catch {
            alertMessage = error.localizedDescription
            return
        }
        for id in ids {
            do {
                try store.deleteKey(keyRefId: id)
            } catch {
                alertMessage = error.localizedDescription
                break
            }
        }
        loadKeys()
    }

    private func importKey(text: String, data: Data, label: String?) {
        do {
            let result = try SSHPrivateKeyValidator.validate(text)
            let resolvedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines)
            let finalLabel = resolvedLabel?.isEmpty == false ? resolvedLabel! : "Imported Key"
            _ = try store.storePrivateKey(
                data: data,
                label: finalLabel,
                keyType: result.keyType,
                requiresPassphrase: result.requiresPassphrase
            )
            loadKeys()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func normalizePrivateKeyData(_ data: Data) throws -> Data {
        let decoded = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .ascii)
        guard var text = decoded else {
            throw NSError(domain: "KeyManagement", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to read key as text"])
        }

        let bomScalars: [UInt32] = [0xFEFF, 0xFFFE, 0xEFBBBF]
        if let firstScalar = text.unicodeScalars.first, bomScalars.contains(firstScalar.value) {
            text.removeFirst()
        }

        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")

        guard let normalized = text.data(using: .utf8) else {
            throw NSError(domain: "KeyManagement", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode normalized key"])
        }

        return normalized
    }

    private func makeDeletionBlockedMessage(hosts: [HostProfile], keyCount: Int) -> String {
        let names = Array(Set(hosts.map { $0.resolvedDisplayName })).sorted()
        let keyPhrase = keyCount == 1 ? "This key is" : "One or more selected keys are"
        if names.count == 1 {
            let updatePhrase = "Update that host to a different key before deleting."
            return "\(keyPhrase) still assigned to the host \"\(names[0])\". \(updatePhrase)"
        }
        let list = names.map { "- \($0)" }.joined(separator: "\n")
        let updatePhrase = "Update those hosts to a different key before deleting."
        return "\(keyPhrase) still assigned to these hosts:\n\(list)\n\(updatePhrase)"
    }
}

struct KeyManagementView: View {
    @StateObject private var viewModel: KeyManagementViewModel
    @State private var isShowingFileImporter = false
    @State private var isShowingPasteSheet = false

    init(hostRepository: HostRepository, keyStore: KeychainPrivateKeyStore) {
        _viewModel = StateObject(
            wrappedValue: KeyManagementViewModel(
                store: keyStore,
                hostRepository: hostRepository
            )
        )
    }

    var body: some View {
        let metrics = AppTheme.metrics
        List {
            if viewModel.keys.isEmpty {
                EmptyStateActionView(
                    title: "No Keys",
                    systemImage: "key.horizontal",
                    description: "Import a private key to get started.",
                    actionTitle: "Import Key",
                    action: { isShowingFileImporter = true }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(viewModel.keys) { key in
                    CardRow {
                        KeyRow(metadata: key)
                    }
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: metrics.rowSpacing / 2, leading: 16, bottom: metrics.rowSpacing / 2, trailing: 16))
                    .swipeActions(edge: .trailing) {
                        Button("Delete", role: .destructive) {
                            Task {
                                if let index = viewModel.keys.firstIndex(where: { $0.id == key.id }) {
                                    await viewModel.deleteKeys(at: IndexSet(integer: index))
                                }
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = key.label
                        } label: {
                            Label("Copy Name", systemImage: "doc.on.doc")
                        }
                        Divider()
                        Button(role: .destructive) {
                            Task {
                                if let index = viewModel.keys.firstIndex(where: { $0.id == key.id }) {
                                    await viewModel.deleteKeys(at: IndexSet(integer: index))
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { offsets in
                    Task { await viewModel.deleteKeys(at: offsets) }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(metrics.rowSpacing)
        .navigationTitle("Keys")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Paste") {
                    isShowingPasteSheet = true
                }
                Button("Import") {
                    isShowingFileImporter = true
                }
            }
        }
        .sheet(isPresented: $isShowingPasteSheet) {
            NavigationStack {
                PasteKeyView { label, text in
                    viewModel.importKeyFromPaste(text: text, label: label)
                    isShowingPasteSheet = false
                }
            }
        }
        .sheet(isPresented: $isShowingFileImporter) {
            KeyFileDocumentPicker { result in
                isShowingFileImporter = false
                switch result {
                case .success(let payload):
                    viewModel.importKeyFromFile(data: payload.data, label: payload.label)
                case .failure(let error):
                    viewModel.alertMessage = error.localizedDescription
                }
            }
        }
        .alert("Keys", isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { _ in viewModel.alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .onAppear {
            viewModel.loadKeys()
        }
        .appScreenBackground()
    }
}

private struct KeyRow: View {
    let metadata: StoredPrivateKeyMetadata
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        VStack(alignment: .leading, spacing: 6) {
            Text(metadata.label)
                .font(AppTheme.typography.headline)
                .foregroundStyle(colors.primaryText)
            HStack(spacing: 8) {
                Text(metadata.keyType.displayName)
                    .font(AppTheme.typography.caption)
                    .foregroundStyle(colors.secondaryText)
                if metadata.requiresPassphrase {
                    Label("Passphrase required", systemImage: "lock.fill")
                        .font(AppTheme.typography.caption)
                        .foregroundStyle(colors.secondaryText)
                }
            }
        }
    }
}

private struct PasteKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    @State private var keyText: String = ""
    let onImport: (_ label: String?, _ text: String) -> Void

    var body: some View {
        Form {
            Section("Label") {
                TextField("My key", text: $label)
            }
            Section("Private Key") {
                TextEditor(text: $keyText)
                    .frame(minHeight: 200)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("Paste Key")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import") {
                    onImport(label.isEmpty ? nil : label, keyText)
                }
                .disabled(keyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .appScreenBackground()
    }
}

private struct KeyFileDocumentPicker: UIViewControllerRepresentable {
    struct Payload {
        let data: Data
        let label: String
    }

    enum PickerError: Error, LocalizedError {
        case cancelled
        case failedToLoad

        var errorDescription: String? {
            switch self {
            case .cancelled:
                return "Import cancelled."
            case .failedToLoad:
                return "Unable to load file."
            }
        }
    }

    let onResult: (Result<Payload, Error>) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.plainText, UTType.text, UTType.data])
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onResult: onResult)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onResult: (Result<Payload, Error>) -> Void

        init(onResult: @escaping (Result<Payload, Error>) -> Void) {
            self.onResult = onResult
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onResult(.failure(PickerError.cancelled))
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else {
                onResult(.failure(PickerError.failedToLoad))
                return
            }
            let access = url.startAccessingSecurityScopedResource()
            defer {
                if access {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            do {
                let data = try Data(contentsOf: url)
                let label = url.deletingPathExtension().lastPathComponent
                onResult(.success(Payload(data: data, label: label)))
            } catch {
                onResult(.failure(error))
            }
        }
    }
}

#Preview {
    NavigationStack {
        KeyManagementView(
            hostRepository: HostRepository(store: JSONStore()),
            keyStore: KeychainPrivateKeyStore()
        )
    }
}
