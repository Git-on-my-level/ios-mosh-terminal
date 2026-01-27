import Foundation

struct MoshConnectInfo: Equatable {
    let udpPort: Int
    let sessionKey: String
    let serverAddress: String
}
