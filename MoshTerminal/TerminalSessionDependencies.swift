import Foundation

struct TerminalSessionDependencies {
    let keyStore: KeychainPrivateKeyStore
    let moshBootstrapper: MoshBootstrapper
    let moshEngineFactory: MoshEngineFactory
}
