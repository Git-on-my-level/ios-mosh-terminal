import SwiftUI

struct StartupDiagnosticsReporterView: View {
    @AppStorage("mosh.startup_diagnostics.json") private var diagnosticsJSON: String = ""

    var body: some View {
        if StartupDiagnostics.shared.diagnosticsJSON != nil {
            Text(diagnosticsJSON)
                .font(.system(size: 8))
                .opacity(0.01)
                .accessibilityIdentifier("mosh.startup_diagnostics.json")
        }
    }
}
