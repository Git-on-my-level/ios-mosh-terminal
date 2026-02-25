import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        List {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(colors.primaryText)

                    Text("Mosh Terminal")
                        .font(AppTheme.typography.headline)
                        .foregroundStyle(colors.primaryText)

                    Text("Version \(version) (\(build))")
                        .font(AppTheme.typography.caption)
                        .foregroundStyle(colors.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                HStack {
                    AppRowLabel("Support", systemImage: "questionmark.circle")
                    Spacer()
                    Text("Contact Support")
                        .font(AppTheme.typography.caption)
                        .foregroundStyle(colors.secondaryText)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    openSupport()
                }

                NavigationLink {
                    TipJarView()
                } label: {
                    AppRowLabel("Tip Jar", systemImage: "heart")
                }

                HStack {
                    AppRowLabel("Source Code", systemImage: "chevron.left.forwardslash.chevron.right")
                    Spacer()
                    Text("View on GitHub")
                        .font(AppTheme.typography.caption)
                        .foregroundStyle(colors.secondaryText)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    openSourceCode()
                }
            }

            Section {
                NavigationLink {
                    LicensesView()
                } label: {
                    AppRowLabel("Licenses", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("About")
        .appScreenBackground()
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    private var supportEmail: String? {
        let rawValue = Bundle.main.infoDictionary?["MoshTerminalSupportEmail"] as? String
        let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }

    private var supportURL: URL? {
        let rawValue = (Bundle.main.infoDictionary?["MoshTerminalSupportURL"] as? String)
            ?? "https://github.com/Git-on-my-level/ios-mosh-terminal/issues"
        return URL(string: rawValue)
    }

    private var sourceCodeURL: URL? {
        URL(string: "https://github.com/Git-on-my-level/ios-mosh-terminal")
    }

    private func openSupport() {
        if let supportEmail {
            var components = URLComponents()
            components.scheme = "mailto"
            components.path = supportEmail
            components.queryItems = [
                URLQueryItem(name: "subject", value: "Mosh Terminal Support (v\(version) build \(build))")
            ]
            if let url = components.url {
                openURL(url)
                return
            }
        }

        if let supportURL {
            openURL(supportURL)
        }
    }

    private func openSourceCode() {
        guard let sourceCodeURL else { return }
        openURL(sourceCodeURL)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
    .environmentObject(TipJarStore())
}
