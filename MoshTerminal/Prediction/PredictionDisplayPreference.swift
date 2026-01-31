import Foundation

enum PredictionDisplayPreference: String, Codable, CaseIterable, Identifiable {
    case off
    case adaptive
    case always
    case experimental

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return "Off"
        case .adaptive:
            return "Adaptive"
        case .always:
            return "Always"
        case .experimental:
            return "Experimental"
        }
    }
}
