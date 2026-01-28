import SwiftUI

struct LicensesView: View {
    private let licenses = LicensesData.items

    var body: some View {
        List {
            Section {
                Text("This app includes open-source components. Their licenses and attributions are listed below.")
                    .foregroundStyle(.secondary)
            }

            Section("Third-Party Software") {
                ForEach(licenses) { license in
                    NavigationLink {
                        LicenseDetailView(license: license)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(license.name)
                            Text(license.licenseName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Licenses")
    }
}

private struct LicenseDetailView: View {
    let license: LicenseItem

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(license.name)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(license.licenseName)
                    .font(.headline)

                Text(license.attribution)
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                Text(license.text)
                    .font(.footnote)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle(license.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        LicensesView()
    }
}
