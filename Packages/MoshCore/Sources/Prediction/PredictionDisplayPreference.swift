import Foundation

public enum PredictionDisplayPreference: String, Codable, CaseIterable, Identifiable {
    case off
    case adaptive
    case always
    case experimental

    public var id: String { rawValue }

    public var displayName: String {
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
