---
agent: codex
done: true
title: App lifecycle + network monitoring services
goal: Provide centralized signals for foreground/background and network changes to drive reconnect behavior later.
---
Provide centralized signals for foreground/background and network changes to drive reconnect behavior later.

## Deliverables
- `AppLifecycleService`:
  - Publishes foreground/background events
- `NetworkPathService` (Network.framework / NWPathMonitor):
  - Publishes path status changes (satisfied/unsatisfied) and interface type where available
- Wiring into the app environment so later connection manager can subscribe

## Non-goals
- No reconnect logic yet
- No UI overlays (optional debug-only is fine)

## Acceptance criteria
- Foreground/background events are reliably emitted
- Network path changes are emitted when toggling network connectivity in simulator/device
