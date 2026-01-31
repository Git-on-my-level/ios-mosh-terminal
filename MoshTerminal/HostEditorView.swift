import SwiftUI

@MainActor
final class HostEditorViewModel: ObservableObject {
    @Published var displayName: String
    @Published var hostname: String
    @Published var username: String
    @Published var sshPortText: String
    @Published var selectedKeyId: String?
    @Published var keyOptions: [StoredPrivateKeyMetadata] = []
    @Published var alertMessage: String?

    private let hostRepository: HostRepository
    private let keyStore: KeychainPrivateKeyStore
    private let existingHost: HostProfile?

    init(
        hostRepository: HostRepository,
        keyStore: KeychainPrivateKeyStore,
        host: HostProfile? = nil
    ) {
        self.hostRepository = hostRepository
        self.keyStore = keyStore
        self.existingHost = host
        self.displayName = host?.displayName ?? ""
        self.hostname = host?.hostname ?? ""
        self.username = host?.username ?? ""
        self.sshPortText = String(host?.sshPort ?? 22)
        self.selectedKeyId = host?.keyRefId
    }

    var isEditing: Bool {
        existingHost != nil
    }

    var isFormValid: Bool {
        validationErrors.isEmpty
    }

    var validationSummary: String {
        if validationErrors.isEmpty {
            return ""
        }
        return validationErrors.joined(separator: "\n")
    }

    func loadKeys() {
        do {
            keyOptions = try keyStore.listKeys()
            if let selectedKeyId,
               !keyOptions.contains(where: { $0.id == selectedKeyId }) {
                self.selectedKeyId = nil
            }
            if selectedKeyId == nil {
                selectedKeyId = keyOptions.first?.id
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    func save(onSuccess: (HostProfile) -> Void) async {
        guard validationErrors.isEmpty else {
            alertMessage = validationSummary
            return
        }
        guard let portValue = portValue else {
            alertMessage = "SSH port must be between 1 and 65535."
            return
        }
        guard let keyRefId = selectedKeyId else {
            alertMessage = "An SSH key is required."
            return
        }
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHostname = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = HostProfile(
            id: existingHost?.id ?? UUID(),
            displayName: trimmedDisplayName,
            hostname: trimmedHostname,
            username: trimmedUsername,
            sshPort: portValue,
            keyRefId: keyRefId,
            lastConnectedAt: existingHost?.lastConnectedAt
        )
        do {
            try await hostRepository.upsert(host)
            onSuccess(host)
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private var validationErrors: [String] {
        var errors: [String] = []
        if hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Hostname is required.")
        }
        if username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Username is required.")
        }
        if portValue == nil {
            errors.append("SSH port must be between 1 and 65535.")
        }
        if selectedKeyId == nil {
            errors.append("An SSH key is required.")
        }
        return errors
    }

    private var portValue: Int? {
        guard let value = Int(sshPortText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        guard (1...65535).contains(value) else {
            return nil
        }
        return value
    }
}

struct HostEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: HostEditorViewModel
    private let hostRepository: HostRepository
    private let keyStore: KeychainPrivateKeyStore
    private let onSave: (HostProfile) -> Void

    init(
        host: HostProfile? = nil,
        hostRepository: HostRepository,
        keyStore: KeychainPrivateKeyStore,
        onSave: @escaping (HostProfile) -> Void
    ) {
        _viewModel = StateObject(
            wrappedValue: HostEditorViewModel(
                hostRepository: hostRepository,
                keyStore: keyStore,
                host: host
            )
        )
        self.hostRepository = hostRepository
        self.keyStore = keyStore
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Display name", text: $viewModel.displayName)
                TextField("Hostname", text: $viewModel.hostname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Username", text: $viewModel.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Connection") {
                TextField("SSH port", text: $viewModel.sshPortText)
                    .keyboardType(.numberPad)
            }

            Section("SSH Key") {
                if viewModel.keyOptions.isEmpty {
                    ContentUnavailableView("No Keys", systemImage: "key.horizontal", description: Text("Import a private key in Settings before saving this host."))
                        .listRowBackground(Color.clear)
                } else {
                    Picker("Key", selection: $viewModel.selectedKeyId) {
                        Text("Select a key").tag(String?.none)
                        ForEach(viewModel.keyOptions, id: \.id) { key in
                            Text(key.label).tag(Optional(key.id))
                        }
                    }
                }
                NavigationLink("Manage Keys") {
                    KeyManagementView(
                        hostRepository: hostRepository,
                        keyStore: keyStore
                    )
                }
            }

            if !viewModel.isFormValid {
                Section {
                    Text(viewModel.validationSummary)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(viewModel.isEditing ? "Edit Host" : "New Host")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    Task {
                        await viewModel.save { host in
                            onSave(host)
                            dismiss()
                        }
                    }
                }
                .disabled(!viewModel.isFormValid)
            }
        }
        .onAppear {
            viewModel.loadKeys()
        }
        .alert(
            "Host Editor",
            isPresented: Binding(get: { viewModel.alertMessage != nil }, set: { _ in viewModel.alertMessage = nil })
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.alertMessage ?? "")
        }
    }
}

#Preview {
    NavigationStack {
        HostEditorView(
            hostRepository: HostRepository(store: JSONStore()),
            keyStore: KeychainPrivateKeyStore(),
            onSave: { _ in }
        )
    }
}
