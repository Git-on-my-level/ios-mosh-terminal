import SwiftUI

struct TerminalView: View {
    let host: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Terminal")
                    .font(.title2)
                    .bold()
                Text("Connected to \(host)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
                .frame(minHeight: 220)
                .overlay(
                    Text("Terminal placeholder")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                )

            Spacer()
        }
        .padding()
        .navigationTitle("Terminal")
    }
}

#Preview {
    NavigationStack {
        TerminalView(host: "Preview")
    }
}
