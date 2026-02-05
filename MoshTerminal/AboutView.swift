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
                    Text("Report an Issue")
                        .font(AppTheme.typography.caption)
                        .foregroundStyle(colors.secondaryText)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    openGitHubIssues()
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

    private func openGitHubIssues() {
        guard let url = URL(string: "https://github.com/Git-on-my-level/ios-mosh-terminal/issues") else {
            return
        }
        openURL(url)
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
}
