import Foundation

struct TrustedHostKey: Codable, Equatable, Hashable {
    var hostname: String
    var port: Int
    var fingerprint: String
    var addedAt: Date

    init(
        hostname: String,
        port: Int,
        fingerprint: String,
        addedAt: Date = Date()
    ) {
        self.hostname = hostname
        self.port = port
        self.fingerprint = fingerprint
        self.addedAt = addedAt
    }
}
