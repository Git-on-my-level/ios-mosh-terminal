import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class KeyManagementViewModel: ObservableObject {
    @Published var keys: [StoredPrivateKeyMetadata] = []
    @Published var alertMessage: String?

    private let store: KeychainPrivateKeyStore

    init(store: KeychainPrivateKeyStore = KeychainPrivateKeyStore()) {
        self.store = store
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

    func deleteKeys(at offsets: IndexSet) {
        let ids = offsets.map { keys[$0].id }
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
}

struct KeyManagementView: View {
    @StateObject private var viewModel = KeyManagementViewModel()
    @State private var isShowingFileImporter = false
    @State private var isShowingPasteSheet = false

    var body: some View {
        List {
            if viewModel.keys.isEmpty {
                ContentUnavailableView("No Keys", systemImage: "key.horizontal", description: Text("Import a private key to get started."))
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.keys) { key in
                    KeyRow(metadata: key)
                }
                .onDelete(perform: viewModel.deleteKeys)
            }
        }
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
        .alert("Key Import", isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { _ in viewModel.alertMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
        .onAppear {
            viewModel.loadKeys()
        }
    }
}

private struct KeyRow: View {
    let metadata: StoredPrivateKeyMetadata

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(metadata.label)
                .font(.headline)
            HStack(spacing: 8) {
                Text(metadata.keyType.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if metadata.requiresPassphrase {
                    Label("Passphrase required", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
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
        KeyManagementView()
    }
}
