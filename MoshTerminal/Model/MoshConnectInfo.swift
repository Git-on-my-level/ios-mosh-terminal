import Foundation

struct MoshConnectInfo: Equatable {
    let udpPort: Int
    let sessionKey: String
    let serverAddress: String
}

enum PersistenceFallbackReason: Equatable {
    case hostPreferencePlainShell
    case tmuxMissingConsentRequired(installCommand: String)
    case tmuxMissingConsentDeclined(installCommand: String)
    case tmuxInstallFailed(installCommand: String, details: String?)
    case tmuxInstallerUnavailable
    case tmuxLaunchFailed(message: String)

    var isWarning: Bool {
        switch self {
        case .hostPreferencePlainShell:
            return false
        case .tmuxMissingConsentRequired,
             .tmuxMissingConsentDeclined,
             .tmuxInstallFailed,
             .tmuxInstallerUnavailable,
             .tmuxLaunchFailed:
            return true
        }
    }
}

enum PersistenceOutcome: Equatable {
    case managedTmuxActive
    case fallbackPlainShell(reason: PersistenceFallbackReason)
}

struct MoshBootstrapResult: Equatable {
    let connectInfo: MoshConnectInfo
    let persistenceOutcome: PersistenceOutcome
}
