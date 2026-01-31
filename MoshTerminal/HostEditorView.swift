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
    @Published var hasAttemptedSave = false

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

    // MARK: - Inline field validation errors

    var hostnameError: String? {
        guard hasAttemptedSave else { return nil }
        let trimmed = hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Hostname is required"
        }
        return nil
    }

    var usernameError: String? {
        guard hasAttemptedSave else { return nil }
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Username is required"
        }
        return nil
    }

    var portError: String? {
        guard hasAttemptedSave else { return nil }
        if portValue == nil {
            return "Port must be 1-65535"
        }
        return nil
    }

    var keyError: String? {
        guard hasAttemptedSave else { return nil }
        if selectedKeyId == nil {
            return "SSH key is required"
        }
        return nil
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
        hasAttemptedSave = true
        guard validationErrors.isEmpty else {
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
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Display name", text: $viewModel.displayName)
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Hostname", text: $viewModel.hostname)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    if let error = viewModel.hostnameError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Username", text: $viewModel.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    if let error = viewModel.usernameError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("Connection") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Port")
                            .foregroundStyle(.secondary)
                        TextField("22", text: $viewModel.sshPortText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    if let error = viewModel.portError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            Section("SSH Key") {
                if viewModel.keyOptions.isEmpty {
                    ContentUnavailableView("No Keys", systemImage: "key.horizontal", description: Text("Import a private key in Settings before saving this host."))
                        .listRowBackground(Color.clear)
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Picker("Key", selection: $viewModel.selectedKeyId) {
                            Text("Select a key").tag(String?.none)
                            ForEach(viewModel.keyOptions, id: \.id) { key in
                                Text(key.label).tag(Optional(key.id))
                            }
                        }
                        if let error = viewModel.keyError {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
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
