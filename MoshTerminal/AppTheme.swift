import SwiftUI

enum AppTheme {
    struct TerminalTheme: Identifiable, Equatable {
        let id: String
        let name: String
        let background: Color
        let foreground: Color
    }

    enum TerminalThemes {
        static let all: [TerminalTheme] = [
            .init(id: "default", name: "Default", background: Color(red: 0.06, green: 0.06, blue: 0.07), foreground: Color(red: 0.92, green: 0.93, blue: 0.95)),
            .init(id: "dracula", name: "Dracula", background: Color(red: 0.16, green: 0.14, blue: 0.21), foreground: Color(red: 0.97, green: 0.97, blue: 0.99)),
            .init(id: "solarized-dark", name: "Solarized Dark", background: Color(red: 0.0, green: 0.17, blue: 0.21), foreground: Color(red: 0.51, green: 0.58, blue: 0.59)),
            .init(id: "solarized-light", name: "Solarized Light", background: Color(red: 0.99, green: 0.96, blue: 0.89), foreground: Color(red: 0.35, green: 0.43, blue: 0.46)),
        ]

        static func theme(id: String) -> TerminalTheme {
            all.first(where: { $0.id == id }) ?? all[0]
        }
    }

    struct Colors: Equatable {
        let background: Color
        let surface: Color
        let surfaceElevated: Color
        let divider: Color
        let primaryText: Color
        let secondaryText: Color
        let accent: Color
        let statusConnected: Color
        let statusConnecting: Color
        let statusError: Color
    }

    struct Metrics {
        let cornerRadius: CGFloat = 16
        let cardPadding: CGFloat = 14
        let rowSpacing: CGFloat = 12
        let iconSize: CGFloat = 18
        let shadowRadius: CGFloat = 8
        let shadowYOffset: CGFloat = 4
    }

    struct Typography {
        let title = Font.system(.largeTitle, design: .rounded).weight(.bold)
        let headline = Font.system(.headline, design: .rounded).weight(.semibold)
        let body = Font.system(.body, design: .rounded)
        let caption = Font.system(.caption, design: .rounded)
        let captionMonospaced = Font.system(.caption, design: .monospaced)
    }

    struct TerminalPalette: Equatable {
        let background: Color
        let foreground: Color
        let statusBarBackground: Color
    }

    static let metrics = Metrics()
    static let typography = Typography()
    static let tintColor: Color = .accentColor

    static func colors(for colorScheme: ColorScheme) -> Colors {
        switch colorScheme {
        case .dark:
            return Colors(
                background: Color(red: 0.06, green: 0.06, blue: 0.07),
                surface: Color(red: 0.12, green: 0.13, blue: 0.15),
                surfaceElevated: Color(red: 0.16, green: 0.17, blue: 0.20),
                divider: Color(red: 0.22, green: 0.23, blue: 0.26),
                primaryText: Color(red: 0.94, green: 0.95, blue: 0.97),
                secondaryText: Color(red: 0.64, green: 0.67, blue: 0.72),
                accent: .accentColor,
                statusConnected: Color(red: 0.32, green: 0.85, blue: 0.48),
                statusConnecting: Color(red: 0.97, green: 0.70, blue: 0.20),
                statusError: Color(red: 0.98, green: 0.38, blue: 0.38)
            )
        case .light:
            return Colors(
                background: Color(red: 0.96, green: 0.97, blue: 0.98),
                surface: Color.white,
                surfaceElevated: Color(red: 0.94, green: 0.95, blue: 0.97),
                divider: Color(red: 0.89, green: 0.90, blue: 0.92),
                primaryText: Color(red: 0.12, green: 0.12, blue: 0.14),
                secondaryText: Color(red: 0.42, green: 0.44, blue: 0.48),
                accent: .accentColor,
                statusConnected: Color(red: 0.20, green: 0.75, blue: 0.40),
                statusConnecting: Color(red: 0.95, green: 0.62, blue: 0.10),
                statusError: Color(red: 0.91, green: 0.26, blue: 0.26)
            )
        @unknown default:
            return Colors(
                background: Color(red: 0.06, green: 0.06, blue: 0.07),
                surface: Color(red: 0.12, green: 0.13, blue: 0.15),
                surfaceElevated: Color(red: 0.16, green: 0.17, blue: 0.20),
                divider: Color(red: 0.22, green: 0.23, blue: 0.26),
                primaryText: Color(red: 0.94, green: 0.95, blue: 0.97),
                secondaryText: Color(red: 0.64, green: 0.67, blue: 0.72),
                accent: .accentColor,
                statusConnected: Color(red: 0.32, green: 0.85, blue: 0.48),
                statusConnecting: Color(red: 0.97, green: 0.70, blue: 0.20),
                statusError: Color(red: 0.98, green: 0.38, blue: 0.38)
            )
        }
    }

    static func terminalPalette(for colorScheme: ColorScheme) -> TerminalPalette {
        let colors = colors(for: colorScheme)
        switch colorScheme {
        case .dark:
            let background = Color(red: 0.06, green: 0.06, blue: 0.07)
            let foreground = Color(red: 0.92, green: 0.93, blue: 0.95)
            return TerminalPalette(
                background: background,
                foreground: foreground,
                statusBarBackground: colors.surfaceElevated
            )
        case .light:
            let background = Color(red: 0.98, green: 0.98, blue: 0.99)
            let foreground = Color(red: 0.12, green: 0.12, blue: 0.14)
            return TerminalPalette(
                background: background,
                foreground: foreground,
                statusBarBackground: colors.surface
            )
        @unknown default:
            let background = Color(red: 0.06, green: 0.06, blue: 0.07)
            let foreground = Color(red: 0.92, green: 0.93, blue: 0.95)
            return TerminalPalette(
                background: background,
                foreground: foreground,
                statusBarBackground: colors.surfaceElevated
            )
        }
    }
}

struct AppScreenBackground: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let colors = AppTheme.colors(for: colorScheme)
        content
            .scrollContentBackground(.hidden)
            .background(colors.background)
    }
}

extension View {
    func appScreenBackground() -> some View {
        modifier(AppScreenBackground())
    }
}

struct CardRow<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let isActive: Bool
    let content: Content

    init(isActive: Bool = false, @ViewBuilder content: () -> Content) {
        self.isActive = isActive
        self.content = content()
    }

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        let metrics = AppTheme.metrics
        let shape = RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)

        HStack(spacing: 0) {
            if isActive {
                Rectangle()
                    .fill(colors.accent)
                    .frame(width: 4)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(metrics.cardPadding)
        }
        .background(shape.fill(colors.surface))
        .overlay(shape.stroke(colors.divider, lineWidth: 1))
        .clipShape(shape)
        .shadow(
            color: colors.divider.opacity(colorScheme == .dark ? 0.25 : 0.4),
            radius: metrics.shadowRadius,
            x: 0,
            y: metrics.shadowYOffset
        )
        .contentShape(shape)
    }
}

struct StatusBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let state: ConnectionManager.State

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        let status = statusStyle(colors: colors)
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 10, weight: .semibold))
            Text(status.label)
        }
        .font(AppTheme.typography.caption)
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(status.color.opacity(colorScheme == .dark ? 0.22 : 0.12))
        .clipShape(Capsule())
        .accessibilityLabel(Text("Status \(state.statusText)"))
    }

    private func statusStyle(colors: AppTheme.Colors) -> (label: String, icon: String, color: Color) {
        switch state {
        case .connected:
            return (state.shortStatusText, "checkmark.circle.fill", colors.statusConnected)
        case .bootstrappingSSH, .connectingUDP, .reconnecting:
            return (state.shortStatusText, "arrow.triangle.2.circlepath", colors.statusConnecting)
        case .failed, .disconnected:
            return (state.shortStatusText, "xmark.octagon.fill", colors.statusError)
        case .idle:
            return (state.shortStatusText, "minus.circle", colors.secondaryText)
        }
    }
}

struct SectionHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(colors.secondaryText)
            .textCase(nil)
            .padding(.leading, 4)
    }
}

struct EmptyStateActionView: View {
    let title: String
    let systemImage: String
    let description: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .semibold))
            Text(title)
                .font(AppTheme.typography.headline)
            Text(description)
                .font(AppTheme.typography.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

struct AppRowLabel: View {
    @Environment(\.colorScheme) private var colorScheme
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        let metrics = AppTheme.metrics
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: metrics.iconSize, weight: .semibold))
                .foregroundStyle(colors.accent)
                .frame(width: metrics.iconSize + 6)
            Text(title)
                .font(AppTheme.typography.body)
                .foregroundStyle(colors.primaryText)
        }
    }
}
