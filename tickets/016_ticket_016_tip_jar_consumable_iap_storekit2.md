# Ticket 016 — Tip jar: Consumable tips (StoreKit 2)

## Goal
Ship a frictionless, App Store–safe tip jar using **consumable** In‑App Purchases, without unlocking features or adding telemetry.

## Guiding choices (review-friendly)
- Use **StoreKit 2**.
- Use **consumable** products so users can tip multiple times.
- Keep wording explicit: “Optional tip. No additional features are unlocked.”
- Avoid external payment links inside the app.

## Proposed products (App Store Connect)
- Consumable: `com.scalingforever.MoshTerminal.tip.small` (e.g., $0.99)
- Consumable: `com.scalingforever.MoshTerminal.tip.medium` (e.g., $2.99)
- Consumable: `com.scalingforever.MoshTerminal.tip.large` (e.g., $6.99)

## UI plan
- Add a new Settings section: **Support Development**
  - “Tip Jar” row → purchase screen
- Tip Jar screen:
  - Show tips with Apple pricing (`Product.displayPrice`)
  - Handle loading, pending, and error states
  - Show a simple “Thank you” confirmation after purchase

## Architecture plan
- `TipJarStore` (ObservableObject, `@MainActor`):
  - Fetches products via `Product.products(for:)`
  - Purchases via `Product.purchase()`, verifies, and finishes transactions
  - Runs a `Transaction.updates` listener at app start to finish tip transactions

## Testing plan
- Manual verification with StoreKit Testing in Xcode:
  - StoreKit config: `MoshTerminal.xcodeproj/xcshareddata/Tips.storekit`
  - Validate purchase, cancel, pending, and repeated purchases

## Rollout plan
1. Launch as **Free + Tip Jar**.
2. Once you have early users, consider moving to **low base price + Tip Jar**.
3. If you later want “premium”, keep it separate as a **non-consumable** or **subscription** (not part of this ticket).

## Non-goals
- Subscriptions
- External payments/links for tips
- Any analytics SDK
