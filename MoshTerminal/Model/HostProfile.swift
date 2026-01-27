import Foundation

struct HostProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var hostname: String
    var username: String
    var sshPort: Int
    var keyRefId: String
    var lastConnectedAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        hostname: String,
        username: String,
        sshPort: Int = 22,
        keyRefId: String,
        lastConnectedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.hostname = hostname
        self.username = username
        self.sshPort = sshPort
        self.keyRefId = keyRefId
        self.lastConnectedAt = lastConnectedAt
    }
}

extension HostProfile {
    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? hostname : trimmed
    }
}
