# AGENTS

## Overview
- iOS app project: `MoshTerminal.xcodeproj` with source in `MoshTerminal/`.
- Core product guidance lives in `CONSTITUTION.md` and `SPEC_V1.md`.
- Work is organized as numbered tickets in `tickets/` (implement in order).

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
