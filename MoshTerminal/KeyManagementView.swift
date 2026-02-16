import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class KeyManagementViewModel: ObservableObject {
    @Published var keys: [StoredPrivateKeyMetadata] = []
    @Published var alertMessage: String?

    private let store: any PrivateKeyManaging
    private let hostRepository: any HostListing

    init(
        store: any PrivateKeyManaging = KeychainPrivateKeyStore(),
        hostRepository: any HostListing = HostRepository(store: JSONStore())
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

    func generateEd25519Key(label: String) -> String? {
        let resolvedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = resolvedLabel.isEmpty ? "Generated Key" : resolvedLabel
        do {
            let generated = try SSHKeyGenerator.generateEd25519OpenSSH(comment: finalLabel)
            _ = try store.storePrivateKey(
                data: Data(generated.privateKeyPEM.utf8),
                label: finalLabel,
                keyType: generated.keyType,
                requiresPassphrase: generated.requiresPassphrase
            )
            loadKeys()
            return generated.publicKey
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
    }

    func publicKeyLine(for key: StoredPrivateKeyMetadata) -> String? {
        do {
            let data = try store.loadPrivateKeyData(keyRefId: key.id)
            guard let text = String(data: data, encoding: .utf8) else {
                alertMessage = "Unable to read key as text."
                return nil
            }
            return try SSHPublicKeyExporter.publicKeyLine(fromPrivateKeyPEM: text, comment: key.label)
        } catch {
            alertMessage = error.localizedDescription
            return nil
        }
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
    @State private var isShowingGenerateSheet = false
    @State private var publicKeySheet: PublicKeySheetPayload?
    @State private var pendingKeyDeletionIds: [String] = []
    @State private var isShowingDeleteConfirmation = false

    init(hostRepository: any HostListing, keyStore: any PrivateKeyManaging) {
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
                    .onTapGesture {
                        showPublicKey(for: key)
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button("Copy") {
                            if let publicKey = viewModel.publicKeyLine(for: key) {
                                UIPasteboard.general.string = publicKey
                            }
                        }
                        .tint(.green)
                        Button("Export") {
                            showPublicKey(for: key)
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) {
                            requestDelete(key)
                        }
                    }
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = key.label
                        } label: {
                            Label("Copy Name", systemImage: "doc.on.doc")
                        }
                        Button {
                            if let publicKey = viewModel.publicKeyLine(for: key) {
                                UIPasteboard.general.string = publicKey
                            }
                        } label: {
                            Label("Copy Public Key", systemImage: "doc.on.doc")
                        }
                        Button {
                            if let publicKey = viewModel.publicKeyLine(for: key) {
                                publicKeySheet = PublicKeySheetPayload(label: key.label, publicKey: publicKey)
                            }
                        } label: {
                            Label("Export Public Key", systemImage: "square.and.arrow.up")
                        }
                        Divider()
                        Button(role: .destructive) {
                            requestDelete(key)
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
        .navigationTitle("Keys")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("Paste") {
                    isShowingPasteSheet = true
                }
                Button("Import") {
                    isShowingFileImporter = true
                }
                Button("Generate") {
                    isShowingGenerateSheet = true
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
        .sheet(isPresented: $isShowingGenerateSheet) {
            NavigationStack {
                GenerateKeyView { label in
                    isShowingGenerateSheet = false
                    if let publicKey = viewModel.generateEd25519Key(label: label ?? "") {
                        publicKeySheet = PublicKeySheetPayload(label: label ?? "Generated Key", publicKey: publicKey)
                    }
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
        .sheet(item: $publicKeySheet) { payload in
            NavigationStack {
                PublicKeyView(label: payload.label, publicKey: payload.publicKey)
            }
        }
        .alert(deleteAlertTitle, isPresented: $isShowingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                pendingKeyDeletionIds = []
            }
            Button(deleteConfirmationButtonTitle, role: .destructive) {
                Task { await confirmKeyDeletion() }
            }
        } message: {
            Text(deleteAlertMessage)
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

    private var deleteAlertTitle: String {
        pendingKeyDeletionIds.count == 1 ? "Delete Key?" : "Delete Keys?"
    }

    private var deleteConfirmationButtonTitle: String {
        pendingKeyDeletionIds.count == 1 ? "Delete Key" : "Delete \(pendingKeyDeletionIds.count) Keys"
    }

    private var deleteAlertMessage: String {
        if pendingKeyDeletionIds.count == 1,
           let key = viewModel.keys.first(where: { $0.id == pendingKeyDeletionIds[0] }) {
            return "Delete \"\(key.label)\"? This cannot be undone."
        }
        return "This will permanently remove the selected keys."
    }

    private func requestDelete(_ key: StoredPrivateKeyMetadata) {
        pendingKeyDeletionIds = [key.id]
        isShowingDeleteConfirmation = true
    }

    private func requestDelete(at offsets: IndexSet) {
        let ids = offsets.map { viewModel.keys[$0].id }
        guard !ids.isEmpty else {
            return
        }
        pendingKeyDeletionIds = ids
        isShowingDeleteConfirmation = true
    }

    private func confirmKeyDeletion() async {
        let ids = pendingKeyDeletionIds
        pendingKeyDeletionIds = []
        guard !ids.isEmpty else {
            return
        }
        await deleteKeys(withIds: ids)
    }

    private func deleteKeys(withIds ids: [String]) async {
        let offsets = IndexSet(
            ids.compactMap { id in
                viewModel.keys.firstIndex(where: { $0.id == id })
            }
        )
        guard !offsets.isEmpty else {
            return
        }
        await viewModel.deleteKeys(at: offsets)
    }

    private func showPublicKey(for key: StoredPrivateKeyMetadata) {
        if let publicKey = viewModel.publicKeyLine(for: key) {
            publicKeySheet = PublicKeySheetPayload(label: key.label, publicKey: publicKey)
        }
    }
}

private struct PublicKeySheetPayload: Identifiable, Equatable {
    let id = UUID()
    let label: String
    let publicKey: String
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
            Text("Tap to copy or export public key")
                .font(AppTheme.typography.caption)
                .foregroundStyle(colors.secondaryText)
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

private struct GenerateKeyView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var label: String = ""
    let onGenerate: (_ label: String?) -> Void

    var body: some View {
        Form {
            Section("Key Type") {
                Text("ED25519")
            }
            Section("Label") {
                TextField("My key", text: $label)
            }
            Section {
                Text("Keys are generated without a passphrase and stored in the iOS Keychain. You can copy/share the public key after generating.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Generate Key")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Generate") {
                    let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
                    onGenerate(trimmed.isEmpty ? nil : trimmed)
                }
            }
        }
        .appScreenBackground()
    }
}

private struct PublicKeyView: View {
    @Environment(\.dismiss) private var dismiss
    let label: String
    let publicKey: String

    var body: some View {
        Form {
            Section("Name") {
                Text(label)
            }
            Section("Public Key") {
                TextEditor(text: .constant(publicKey))
                    .frame(minHeight: 180)
                    .font(.system(.body, design: .monospaced))
            }
        }
        .navigationTitle("Public Key")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItemGroup(placement: .confirmationAction) {
                Button("Copy") {
                    UIPasteboard.general.string = publicKey
                }
                ShareLink(item: publicKey) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
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
        let previewDeps = AppEnvironment.makePreviewDependencies()
        KeyManagementView(
            hostRepository: previewDeps.hostRepository,
            keyStore: previewDeps.keyStore
        )
    }
}
