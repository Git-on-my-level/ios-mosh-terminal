import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) private var openURL
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Image(systemName: "terminal.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.primary)
                    
                    Text("Mosh Terminal")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Text("Version \(version) (\(build))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            Section("Support") {
                HStack {
                    Label("Support", systemImage: "questionmark.circle")
                    Spacer()
                    Text("Report an Issue")
                        .foregroundStyle(.secondary)
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
                    Label("Licenses", systemImage: "doc.text")
                }
            }
        }
        .navigationTitle("About")
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
