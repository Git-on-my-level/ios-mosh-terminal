import StoreKit
import SwiftUI

struct TipJarView: View {
    @EnvironmentObject private var tipJar: TipJarStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        Form {
            Section {
                Text("Optional tip. No additional features are unlocked.")
                    .font(AppTheme.typography.caption)
                    .foregroundStyle(colors.secondaryText)
            }

            Section {
                switch tipJar.loadState {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case .failed(let message):
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tips are unavailable right now.")
                            .font(AppTheme.typography.body)
                            .foregroundStyle(colors.primaryText)
                        Text(message)
                            .font(AppTheme.typography.caption)
                            .foregroundStyle(colors.secondaryText)
                        Button("Try Again") {
                            Task { await tipJar.loadProducts() }
                        }
                    }
                    .padding(.vertical, 4)
                case .loaded:
                    ForEach(tipJar.products, id: \.id) { product in
                        TipProductRow(product: product)
                    }
                }
            } header: {
                SectionHeader("Tip Jar")
            }
        }
        .navigationTitle("Support Development")
        .alert(item: $tipJar.alert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .task {
            tipJar.start()
            if case .idle = tipJar.loadState {
                await tipJar.loadProducts()
            }
        }
        .appScreenBackground()
    }
}

private struct TipProductRow: View {
    let product: Product
    @EnvironmentObject private var tipJar: TipJarStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        Button {
            Task { await tipJar.purchase(product) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(colors.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName)
                        .font(AppTheme.typography.body)
                        .foregroundStyle(colors.primaryText)
                    Text(product.description)
                        .font(AppTheme.typography.caption)
                        .foregroundStyle(colors.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                if tipJar.purchasingProductID == product.id {
                    ProgressView()
                } else {
                    Text(product.displayPrice)
                        .font(AppTheme.typography.caption)
                        .foregroundStyle(colors.secondaryText)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(tipJar.purchasingProductID != nil)
    }
}
