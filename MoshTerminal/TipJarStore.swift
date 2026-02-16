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

    private static let tipTiers = ["tip.small", "tip.medium", "tip.large"]
    private static let fallbackPrefixes = [
        "com.scalingforever.MoshTerminal",
        "com.scalingforever.moshterminal",
    ]
    private static let maxProductLoadAttempts = 3
    private static let retryBaseDelayNanoseconds: UInt64 = 500_000_000

    @Published private(set) var products: [Product] = []
    @Published private(set) var loadState: LoadState = .idle
    @Published var purchasingProductID: String?
    @Published var alert: TipJarAlert?

    private var hasStarted = false
    private var transactionUpdatesTask: Task<Void, Never>?
    private let productIDs: [String]

    init(productIDs: [String]? = nil) {
        self.productIDs = productIDs ?? Self.resolveProductIDs()
    }

    deinit {
        transactionUpdatesTask?.cancel()
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        transactionUpdatesTask = Task.detached {
            await TipJarTransactionObserver.observe(productIDs: self.productIDs)
        }
    }

    func loadProducts() async {
        guard loadState != .loading else { return }
        loadState = .loading

        debugLog("Loading products for bundle=\(Bundle.main.bundleIdentifier ?? "nil"), ids=\(productIDs)")
        debugLog("STOREKIT_CONFIG_PATH=\(ProcessInfo.processInfo.environment["STOREKIT_CONFIG_PATH"] ?? "not set")")

        do {
            let fetched = try await fetchProductsWithRetry()
            guard !fetched.isEmpty else {
                loadState = .failed(
                    "No tip products were returned. Expected IDs: \(productIDs.joined(separator: ", "))\(debugFailureDetails())"
                )
                debugLog("No products returned after all attempts.")
                return
            }
            products = fetched.sorted { lhs, rhs in
                if lhs.price == rhs.price {
                    return lhs.id < rhs.id
                }
                return lhs.price < rhs.price
            }
            loadState = .loaded
            debugLog("Loaded products: \(products.map(\.id).joined(separator: ", "))")
        } catch is CancellationError {
            loadState = .idle
            debugLog("Load cancelled")
        } catch {
            loadState = .failed("StoreKit error: \(error.localizedDescription)")
            debugLog("StoreKit error: \(error.localizedDescription)")
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

    private static func resolveProductIDs() -> [String] {
        if let configuredIDs = Bundle.main.object(forInfoDictionaryKey: "TIP_JAR_PRODUCT_IDS") as? [String] {
            let trimmed = configuredIDs
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !trimmed.isEmpty {
                var deduped: [String] = []
                var seen = Set<String>()
                for id in trimmed where seen.insert(id).inserted {
                    deduped.append(id)
                }
                return deduped
            }
        }

        var prefixes: [String] = []
        if let bundleID = Bundle.main.bundleIdentifier, !bundleID.isEmpty {
            prefixes.append(bundleID)
            let lowercasedBundleID = bundleID.lowercased()
            if lowercasedBundleID != bundleID {
                prefixes.append(lowercasedBundleID)
            }
        }
        prefixes.append(contentsOf: fallbackPrefixes)

        var productIDs: [String] = []
        var seen = Set<String>()
        for prefix in prefixes {
            for tier in tipTiers {
                let id = "\(prefix).\(tier)"
                guard seen.insert(id).inserted else { continue }
                productIDs.append(id)
            }
        }
        return productIDs
    }

    private func fetchProductsWithRetry() async throws -> [Product] {
        let batches = Self.productIDLookupBatches(from: productIDs)
        var lastError: Error?

        for ids in batches {
            for attempt in 1...Self.maxProductLoadAttempts {
                try Task.checkCancellation()
                do {
                    debugLog("Product lookup attempt \(attempt) for ids=\(ids)")
                    let fetched = try await Product.products(for: ids)
                    if !fetched.isEmpty {
                        debugLog("Lookup succeeded with \(fetched.count) product(s).")
                        return fetched
                    }
                    debugLog("Lookup returned 0 products.")
                } catch {
                    lastError = error
                    debugLog("Lookup failed: \(error.localizedDescription)")
                }

                guard attempt < Self.maxProductLoadAttempts else { break }
                let delay = Self.retryBaseDelayNanoseconds * UInt64(attempt)
                try await Task.sleep(nanoseconds: delay)
            }
        }

        if let lastError {
            throw lastError
        }
        return []
    }

    private static func productIDLookupBatches(from productIDs: [String]) -> [[String]] {
        let normalized = deduplicated(productIDs)
        guard !normalized.isEmpty else { return [productIDs] }

        let lowercased = deduplicated(normalized.map { $0.lowercased() })
        if lowercased != normalized {
            return [normalized, lowercased]
        }
        return [normalized]
    }

    private static func deduplicated(_ ids: [String]) -> [String] {
        var deduped: [String] = []
        var seen = Set<String>()
        for id in ids where seen.insert(id).inserted {
            deduped.append(id)
        }
        return deduped
    }

    private func debugLog(_ message: String) {
#if DEBUG
        print("[TipJarStore] \(message)")
#endif
    }

    private func debugFailureDetails() -> String {
#if DEBUG
        let bundleID = Bundle.main.bundleIdentifier ?? "nil"
        let storeKitPath = ProcessInfo.processInfo.environment["STOREKIT_CONFIG_PATH"] ?? "not set"
        return "\n\nDebug: bundle=\(bundleID), STOREKIT_CONFIG_PATH=\(storeKitPath)"
#else
        return ""
#endif
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
