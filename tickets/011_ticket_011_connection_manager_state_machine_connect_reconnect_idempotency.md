# Ticket 011 — Connection manager + state machine (connect/reconnect/idempotency)

## Goal
Implement the v1 connection state machine and make reconnect reliable.

## Deliverables
- `ConnectionManager` per-host (or single active connection) with states:
  - idle
  - bootstrappingSSH
  - connectingUDP
  - connected
  - reconnecting
  - failed(error)
- Idempotent triggers:
  - Multiple “connect” calls do not overlap; prior attempt is cancelled/ignored safely
- Reconnect triggers:
  - App foreground
  - Network becomes satisfied
- Reconnect strategy:
  - Try UDP resume briefly if possible
  - Fallback to SSH bootstrap when needed
- UI state propagation to Hosts list and Terminal status bar

## Non-goals
- Multi-session concurrency (v1 supports one active terminal at a time)
- Background keepalive

## Acceptance criteria
- Putting the app in background and returning results in automatic reconnect attempts
- Network toggles trigger reconnect without user re-entering credentials
- Reconnect does not spawn multiple overlapping sessions
