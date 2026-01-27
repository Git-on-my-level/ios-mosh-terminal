# Ticket 005 — Hosts UI (CRUD) wired to persistence + key selection

## Goal
Implement the real Hosts list and Host editor UI for v1.

## Deliverables
- Hosts list UI:
  - List all saved `HostProfile`s
  - Add (+) opens Host editor
  - Edit action
  - Delete (swipe)
  - Tap host → navigates to Terminal screen (connect action can still be stubbed)
- Host editor:
  - Validate required fields
  - Select imported key (choose from Keychain-backed key refs)
  - Save persists to repository

## Non-goals
- No networking
- No terminal engine

## Acceptance criteria
- Hosts can be created/edited/deleted and persist
- Host row shows at least hostname/username and lastConnectedAt (if present)
- Host requires an associated key before save
