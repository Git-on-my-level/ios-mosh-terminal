# Ticket 004 — Key import + Keychain storage

## Goal
Support importing SSH private keys and storing them securely.

## Deliverables
- Keychain wrapper:
  - Store private key bytes under an opaque `keyRefId`
  - Delete key by `keyRefId`
  - Retrieve key bytes by `keyRefId`
- Import flows:
  - Import from Files (UIDocumentPicker)
  - Import from paste (multiline text)
- Basic validation:
  - Detect OpenSSH private key formats (RSA/ED25519) and reject obviously invalid input
  - Detect encrypted keys and mark them as “requires passphrase”
- Passphrase UX:
  - On connect (later), if key is encrypted, prompt for passphrase (do not store passphrase)

## Non-goals
- No key generation
- No agent forwarding
- No password-based SSH auth

## Acceptance criteria
- A key can be imported and stored in Keychain, then retrieved after app relaunch
- A key can be deleted and is no longer available
- Host editor can reference a stored key via `keyRefId`
