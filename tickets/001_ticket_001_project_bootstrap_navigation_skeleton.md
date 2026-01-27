# Ticket 001 — Project bootstrap + navigation skeleton

## Goal
Create an iOS app skeleton that compiles and runs, with the core navigation structure in place.

## Deliverables
- Xcode project (Swift + SwiftUI) targeting iOS/iPadOS 17.0+
- App navigation with 2–3 top-level destinations:
  - Hosts list (default)
  - Settings
  - Terminal screen (placeholder)
- Minimal shared app theming (system-based) and environment wiring (dependency container stub)

## Non-goals
- No networking
- No third-party libs yet
- No keychain work

## Acceptance criteria
- App builds and runs on iPhone + iPad simulators
- Hosts list screen is reachable and shows placeholder content
- Settings screen is reachable and shows placeholder toggles
- Terminal screen is reachable via a stub “Connect” action
