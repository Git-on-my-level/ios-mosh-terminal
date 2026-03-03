import StoreKit
import SwiftUI

struct TipJarView: View {
    @EnvironmentObject private var tipJar: TipJarStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let colors = AppTheme.colors(for: colorScheme)
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Optional tip.")
                        .font(AppTheme.typography.headline)
                        .foregroundStyle(colors.secondaryText)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("No additional features are unlocked.")
                            .font(AppTheme.typography.caption)
                            .foregroundStyle(colors.secondaryText)

                        Text("Your support helps fund open source development of this project.")
                            .font(AppTheme.typography.caption)
                            .foregroundStyle(colors.secondaryText)
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                switch tipJar.loadState {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                case .failed:
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tips are currently unavailable.")
                            .font(AppTheme.typography.body)
                            .foregroundStyle(colors.primaryText)
                        Text("Please try again later.")
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
