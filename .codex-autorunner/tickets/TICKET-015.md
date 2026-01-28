---
agent: codex
done: true
title: Connection liveness + error mapping for ConnectionManager
goal: Detect when UDP/Mosh session is not viable and surface actionable failures.
---

## Context
ConnectionManager expects the engine to signal `.disconnected` or `.failed(error)`.
Mosh itself can keep trying forever, but this app wants to recover quickly (resume or re-bootstrap).

## Deliverables
1. Liveness heuristics in runtime (minimal, practical)
   - Track:
     - `lastHeardMillis` (any inbound packet)
     - `lastRoundtripSuccessMillis` (when an inbound packet acks our sent state, or any RTT update)
   - Define thresholds:
     - If no inbound packets for e.g. 15s → mark `.disconnected`
     - If repeated sendto errors like `ENETUNREACH` / `EHOSTUNREACH` → `.failed(startFailed: ...)`
     - If decrypt/integrity check fails repeatedly → `.failed`

   (Exact numbers can be tuned; document rationale.)

2. UDP-blocked detection (best-effort)
   - After start:
     - If we never receive a valid packet within ConnectionManager’s connect timeout,
       engine should end in `.disconnected` (so manager re-bootstrap may occur).
   - If SSH bootstrap succeeds but UDP never works, the UI should show
     “This network appears to block UDP. Mosh requires UDP.”
     (ConnectionErrorMapper already does some mapping; ensure your errors map cleanly.)

3. Stop behavior on background
   - When app backgrounds, ConnectionManager calls stopEngine; ensure runtime stops quickly.

## Acceptance criteria
- Simulate “UDP blackhole” by pointing to a non-routable address:
  - engine transitions to `.disconnected` within a bounded time.
- Corrupt datagrams do not crash the engine; they are counted and ignored until a threshold.

## Notes
- Be careful not to treat out-of-order packets as “corrupt”.
- Never include the session key in error messages/logs.

## Completion Notes
- Added liveness tracking in `MoshRuntime` with inbound silence timeout, corrupt packet thresholding, and UDP unreachable send error handling.
- Mapped UDP-blocked failures to the requested user-facing message and added integrity failure mapping.
