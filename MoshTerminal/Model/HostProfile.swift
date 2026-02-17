import Foundation

enum SessionPersistenceMode: String, Codable, Equatable, Sendable {
    case managedTmux
    case plainShell
}

enum TmuxSetupConsent: String, Codable, Equatable, Sendable {
    case unknown
    case approved
    case declined
}

struct HostProfile: Identifiable, Codable, Equatable {
    let id: UUID
    var displayName: String
    var hostname: String
    var username: String
    var sshPort: Int
    var keyRefId: String
    var lastConnectedAt: Date?
    var sessionPersistenceMode: SessionPersistenceMode
    var tmuxSetupConsent: TmuxSetupConsent

    init(
        id: UUID = UUID(),
        displayName: String,
        hostname: String,
        username: String,
        sshPort: Int = 22,
        keyRefId: String,
        lastConnectedAt: Date? = nil,
        sessionPersistenceMode: SessionPersistenceMode = .managedTmux,
        tmuxSetupConsent: TmuxSetupConsent = .unknown
    ) {
        self.id = id
        self.displayName = displayName
        self.hostname = hostname
        self.username = username
        self.sshPort = sshPort
        self.keyRefId = keyRefId
        self.lastConnectedAt = lastConnectedAt
        self.sessionPersistenceMode = sessionPersistenceMode
        self.tmuxSetupConsent = tmuxSetupConsent
    }

    enum CodingKeys: String, CodingKey {
        case id
        case displayName
        case hostname
        case username
        case sshPort
        case keyRefId
        case lastConnectedAt
        case sessionPersistenceMode
        case tmuxSetupConsent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        hostname = try container.decode(String.self, forKey: .hostname)
        username = try container.decode(String.self, forKey: .username)
        sshPort = try container.decode(Int.self, forKey: .sshPort)
        keyRefId = try container.decode(String.self, forKey: .keyRefId)
        lastConnectedAt = try container.decodeIfPresent(Date.self, forKey: .lastConnectedAt)
        sessionPersistenceMode = try container.decodeIfPresent(
            SessionPersistenceMode.self,
            forKey: .sessionPersistenceMode
        ) ?? .managedTmux
        tmuxSetupConsent = try container.decodeIfPresent(
            TmuxSetupConsent.self,
            forKey: .tmuxSetupConsent
        ) ?? .unknown
    }
}

extension HostProfile {
    var resolvedDisplayName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? hostname : trimmed
    }
}
