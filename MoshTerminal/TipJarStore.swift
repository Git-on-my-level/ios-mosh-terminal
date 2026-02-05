import Foundation
import StoreKit

@MainActor
final class TipJarStore: ObservableObject {
    struct TipJarAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    static let productIDs: [String] = [
        "com.scalingforever.MoshTerminal.tip.small",
        "com.scalingforever.MoshTerminal.tip.medium",
        "com.scalingforever.MoshTerminal.tip.large",
    ]

    @Published private(set) var products: [Product] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published var purchasingProductID: String?
    @Published var alert: TipJarAlert?

    private var hasStarted = false
    private var transactionUpdatesTask: Task<Void, Never>?

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        transactionUpdatesTask = Task.detached {
            await TipJarTransactionObserver.observe(productIDs: Self.productIDs)
        }
    }

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            guard !fetched.isEmpty else {
                loadState = .failed("No tip products are available.")
                return
            }
            products = fetched.sorted { lhs, rhs in
                if lhs.price == rhs.price {
                    return lhs.id < rhs.id
                }
                return lhs.price < rhs.price
            }
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func purchase(_ product: Product) async {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    alert = TipJarAlert(
                        title: "Thank you!",
                        message: "Optional tip received. No additional features are unlocked."
                    )
                case .unverified(_, let verificationError):
                    alert = TipJarAlert(
                        title: "Purchase Unverified",
                        message: verificationError.localizedDescription
                    )
                }
            case .pending:
                alert = TipJarAlert(
                    title: "Purchase Pending",
                    message: "This tip is pending approval. You’ll be charged if it’s approved."
                )
            case .userCancelled:
                break
            @unknown default:
                alert = TipJarAlert(
                    title: "Purchase Incomplete",
                    message: "Unable to complete the purchase."
                )
            }
        } catch {
            alert = TipJarAlert(
                title: "Purchase Failed",
                message: error.localizedDescription
            )
        }
    }

}

private enum TipJarTransactionObserver {
    static func observe(productIDs: [String]) async {
        for await update in Transaction.updates {
            guard case .verified(let transaction) = update else { continue }
            guard productIDs.contains(transaction.productID) else { continue }
            await transaction.finish()
        }
    }
}
