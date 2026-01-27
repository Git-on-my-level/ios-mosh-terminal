import SwiftUI

struct LicensesView: View {
    var body: some View {
        List {
            Section {
                Text("Third-party licenses will appear here once dependencies are integrated.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Licenses")
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}
