import SwiftUI

enum AppTheme {
    struct TerminalPalette: Equatable {
        let background: Color
        let foreground: Color
        let statusBarBackground: Color
    }

    static let tintColor: Color = .accentColor

    static func terminalPalette(for colorScheme: ColorScheme) -> TerminalPalette {
        switch colorScheme {
        case .dark:
            let background = Color(red: 0.06, green: 0.06, blue: 0.07)
            let foreground = Color(red: 0.92, green: 0.93, blue: 0.95)
            return TerminalPalette(
                background: background,
                foreground: foreground,
                statusBarBackground: background.opacity(0.85)
            )
        case .light:
            let background = Color(red: 0.98, green: 0.98, blue: 0.99)
            let foreground = Color(red: 0.12, green: 0.12, blue: 0.14)
            return TerminalPalette(
                background: background,
                foreground: foreground,
                statusBarBackground: background.opacity(0.92)
            )
        @unknown default:
            let background = Color(red: 0.06, green: 0.06, blue: 0.07)
            let foreground = Color(red: 0.92, green: 0.93, blue: 0.95)
            return TerminalPalette(
                background: background,
                foreground: foreground,
                statusBarBackground: background.opacity(0.85)
            )
        }
    }
}
