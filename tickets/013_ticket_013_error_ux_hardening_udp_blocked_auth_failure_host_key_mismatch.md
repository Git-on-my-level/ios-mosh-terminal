# Ticket 013 — Error UX hardening (UDP blocked, auth failure, host key mismatch)

## Goal
Make failures understandable and actionable, with minimal UI friction.

## Deliverables
- Error mapping layer:
  - SSH auth failure (bad key/passphrase)
  - Host key mismatch
  - `mosh-server` missing
  - UDP blocked/unreachable
  - Generic network unreachable
- Terminal screen shows:
  - small state banner (connected/reconnecting/disconnected)
  - non-modal error presentation where possible
- “Retry” and “Back” actions for recoverable errors

## Non-goals
- Fancy diagnostics
- Log sharing UI

## Acceptance criteria
- Each major failure mode produces a distinct message that tells the user what to do next
- No sensitive values appear in error strings
