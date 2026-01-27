# AGENTS

## Overview
- iOS app project: `MoshTerminal.xcodeproj` with source in `MoshTerminal/`.
- Core product guidance lives in `CONSTITUTION.md` and `SPEC_V1.md`.
- Work is organized as numbered tickets in `tickets/` (implement in order).

## Build (simulator)
- Command-line simulator build: `./scripts/build_sim.sh`
- Override simulator destination if needed via `DESTINATION`, for example:
  - `DESTINATION="platform=iOS Simulator,name=iPhone 17 Pro" ./scripts/build_sim.sh`

## Keep This File Useful
- Update this file with high-level, timeless context that helps new agents orient quickly.
- Avoid machine-specific paths, exact tool versions, or other time-sensitive details.
