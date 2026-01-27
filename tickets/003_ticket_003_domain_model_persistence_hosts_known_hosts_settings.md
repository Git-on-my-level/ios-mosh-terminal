# Ticket 003 — Domain model + persistence (hosts, known-hosts, settings)

## Goal
Create the local data model and persistence layer needed for v1.

## Deliverables
- Codable models:
  - `HostProfile` (id, displayName, hostname, username, sshPort, keyRefId, lastConnectedAt)
  - `TrustedHostKey` (hostname, port, fingerprint, addedAt)
- Persistence:
  - Versioned JSON store in Application Support
  - CRUD repository APIs for hosts and trusted host keys
- Unit tests for:
  - Load/save roundtrip
  - Basic migration versioning (v1 schema)

## Non-goals
- No keychain storage for private keys yet
- No networking

## Acceptance criteria
- Hosts can be created/edited/deleted and persist across app relaunch
- Trusted host keys can be stored and retrieved deterministically
- Unit tests pass
