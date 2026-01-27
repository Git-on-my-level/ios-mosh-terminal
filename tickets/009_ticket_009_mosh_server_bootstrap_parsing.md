# Ticket 009 — `mosh-server` bootstrap + parsing

## Goal
Start `mosh-server` over SSH, parse connection info, and return a `MoshConnectInfo`.

## Deliverables
- `MoshBootstrapper` service that:
  - Runs `mosh-server` remotely (or `mosh-server new`) via SSH
  - Parses a line matching `MOSH CONNECT <udpPort> <key>`
  - Returns:
    - `udpPort` (Int)
    - `sessionKey` (base64 string)
    - `serverAddress` (host/addr used)
- User-visible errors for:
  - `mosh-server` missing or not executable
  - Non-UTF8 locale issues (if encountered)
  - Unexpected output format

## Non-goals
- Implementing the Mosh protocol
- UI polish beyond essential errors

## Acceptance criteria
- On a real host with mosh installed, bootstrap returns valid port + key
- On a host without mosh, user sees an actionable “install mosh-server” message
