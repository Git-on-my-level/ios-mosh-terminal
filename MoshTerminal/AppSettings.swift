import SwiftUI

final class AppSettings: ObservableObject {
    enum ThemeMode: String, CaseIterable, Identifiable {
        case system
        case light
        case dark

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system:
                return "System"
            case .light:
                return "Light"
            case .dark:
                return "Dark"
            }
        }

        var preferredColorScheme: ColorScheme? {
            switch self {
            case .system:
                return nil
            case .light:
                return .light
            case .dark:
                return .dark
            }
        }
    }

    private enum Keys {
        static let fontSize = "settings.fontSize"
        static let themeMode = "settings.themeMode"
        static let keepAwake = "settings.keepAwake"
#if DEBUG
        static let debugOverlayEnabled = "settings.debugOverlayEnabled"
#endif
    }

    private let defaults: UserDefaults

    @Published var fontSize: Double {
        didSet {
            defaults.set(fontSize, forKey: Keys.fontSize)
        }
    }

    @Published var themeMode: ThemeMode {
        didSet {
            defaults.set(themeMode.rawValue, forKey: Keys.themeMode)
        }
    }

    @Published var keepAwake: Bool {
        didSet {
            defaults.set(keepAwake, forKey: Keys.keepAwake)
        }
    }

#if DEBUG
    @Published var debugOverlayEnabled: Bool {
        didSet {
            defaults.set(debugOverlayEnabled, forKey: Keys.debugOverlayEnabled)
        }
    }
#endif

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedFontSize = defaults.object(forKey: Keys.fontSize) as? Double ?? 14
        fontSize = storedFontSize.clamped(to: 10...24)
        if let storedTheme = defaults.string(forKey: Keys.themeMode),
           let themeMode = ThemeMode(rawValue: storedTheme) {
            self.themeMode = themeMode
        } else {
            themeMode = .system
        }
        keepAwake = defaults.object(forKey: Keys.keepAwake) as? Bool ?? false

#if DEBUG
        debugOverlayEnabled = defaults.object(forKey: Keys.debugOverlayEnabled) as? Bool ?? false
#endif
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
