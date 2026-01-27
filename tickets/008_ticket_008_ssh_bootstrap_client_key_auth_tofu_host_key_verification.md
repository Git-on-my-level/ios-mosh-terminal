# Ticket 008 — SSH bootstrap client (key auth + TOFU host-key verification)

## Goal
Implement SSH connectivity sufficient to start `mosh-server`.

## Deliverables
- `SSHClient` protocol (mockable) with:
  - Connect(host, port, username, privateKey, passphrase?)
  - Fetch server host key fingerprint
  - Execute remote command and capture stdout/stderr + exit status
  - Disconnect/cancel
- Concrete implementation using chosen library (e.g., libssh2)
- TOFU host-key verification:
  - On first connect: display fingerprint and require user Trust/Cancel
  - Store trusted fingerprint
  - On mismatch: fail with explicit error

## Non-goals
- Password auth (disallowed)
- Jump hosts
- Port forwarding
- SFTP/SCP

## Acceptance criteria
- Can SSH to a real host using an imported key and run `echo ok`
- First connect prompts to trust fingerprint and persists it
- Subsequent connect succeeds without prompt
- Host key mismatch is detected and blocked with clear messaging
