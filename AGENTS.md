# AGENTS

## Overview
- iOS app project: `MoshTerminal.xcodeproj` with source in `MoshTerminal/`.
- Core product guidance lives in `CONSTITUTION.md` and `SPEC_V1.md`.
- Work is organized as numbered tickets in `tickets/` (implement in order).

## GitHub Access
- This is a **private repository**. Use `gh` CLI for authenticated access.
- Fetching issues: `gh issue view <number> --repo Git-on-my-level/ios-mosh-terminal`
- Downloading assets (images, etc.): `gh api -H "Accept: application/octet-stream" "<asset-url>" > file.png`
- Regular `curl` or `wget` will fail on private asset URLs.

## Architecture

- **UI Framework**: SwiftUI with UIKit bridging for terminal (SwiftTerm)
- **Pattern**: MVVM-ish - views have companion `*ViewModel` classes with `@Published` state
- **Navigation**: TabView (Hosts/Settings) with NavigationStack per tab

### Key Files by Feature

| Feature | View | ViewModel |
|---------|------|-----------|
| Terminal session | `TerminalView.swift` | `TerminalSessionViewModel.swift` |
| Host list | `HostsListView.swift` | `HostsListViewModel` (in same file) |
| Host editor | `HostEditorView.swift` | `HostEditorViewModel` (in same file) |
| Settings | `SettingsView.swift` | - |
| Key management | `KeyManagementView.swift` | `KeyManagementViewModel` (in same file) |

### Dependencies

- **SwiftTerm**: Terminal emulator, wrapped via `TerminalContainerView` (UIViewRepresentable)
- **libssh2**: SSH client (via xcframework in `Frameworks/`)

## Build (simulator)
- Command-line simulator build: `./scripts/build_sim.sh`
- Override simulator destination if needed via `DESTINATION`, for example:
  - `DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro" ./scripts/build_sim.sh`

## Test (simulator)
- Run tests: `./scripts/test_sim.sh`
- If the simulator fails to launch the test runner (preflight/busy), reset the simulator and wait for it to finish booting:
  - `xcrun simctl erase "iPhone 17 Pro"`
  - `xcrun simctl boot "iPhone 17 Pro" && xcrun simctl bootstatus "iPhone 17 Pro" -b`

## Keep This File Useful
- Update this file with high-level, timeless context that helps new agents orient quickly.
- Avoid machine-specific paths, exact tool versions, or other time-sensitive details.
