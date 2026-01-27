# Ticket 002 — Dependency + licensing plan (freeze the approach)

## Goal
De-risk the project by selecting the dependency stack and documenting license/compliance requirements before deep integration.

## Deliverables
- `docs/DEPENDENCIES.md` documenting:
  - Terminal emulator choice (recommended: SwiftTerm)
  - SSH library choice (e.g., libssh2 wrapper) and crypto dependencies
  - Mosh engine approach:
    - Option A (fastest): embed upstream Mosh client code (GPL obligations)
    - Option B (hard): independent protocol implementation (non-goal for v1 unless explicitly chosen)
  - For each dependency: license, attribution requirements, and integration method (SPM vs XCFramework)
- Add chosen dependencies to the project:
  - SPM where available
  - XCFramework build pipeline stub (if needed) with placeholder scripts
- `About → Licenses` placeholder screen that can list dependencies later

## Non-goals
- Do not implement SSH/Mosh behavior yet
- No UI polish

## Acceptance criteria
- Project builds with dependency placeholders integrated (even if feature flags are off)
- `docs/DEPENDENCIES.md` exists and explicitly states the v1 plan and compliance steps
