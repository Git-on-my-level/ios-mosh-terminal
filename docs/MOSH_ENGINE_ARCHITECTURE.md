# MoshEngine Architecture (v1)

## Intent
MoshEngine is a clean-room, permissively licensed implementation of the Mosh client protocol. It MUST NOT reuse or link upstream GPL Mosh client code. Only public protocol behavior and documentation are referenced.

## Protocol Scope (v1)

### Bootstrap handshake
- SSH is used only to launch `mosh-server` and obtain the connection line:
  - `MOSH CONNECT <udpPort> <base64Key>`
- MoshEngine receives the UDP port and session key and starts a UDP session to the server host/port.

### UDP transport
- Use UDP sockets for all Mosh traffic.
- The engine must tolerate packet loss, duplication, and reordering.
- Session resumption is attempted on app foreground or network changes; if it fails quickly, the app re-bootstraps via SSH.

### Crypto primitives (high-level)
- Use the session key from `mosh-server` to derive symmetric encryption + authentication material.
- Apply authenticated encryption to all payloads; include nonces and integrity checks per datagram.
- Provide replay protection via sequence numbers and windowing.

### Input/output framing
- Encode local input bytes into protocol payloads.
- Decode remote payloads into terminal output bytes.
- Track sequence numbers and acknowledgements to drive state synchronization.

### Resize handling
- Send terminal size changes immediately on orientation or keyboard state changes.
- Re-send the current size on reconnect/resume.

## Non-goals (v1)
- Reuse of upstream GPL Mosh client code or direct code translation.
- Full compatibility with all historical protocol versions.
- Advanced roaming heuristics beyond basic reconnect/resume.
- Server-side implementation (`mosh-server`) or SSH-only sessions.
- Non-interactive workflows (file transfer, port forwarding, SCP/SFTP).

## Notes for Implementation Tickets
- Keep MoshEngine isolated behind a protocol-agnostic interface so it can be tested with mock UDP transports.
- Document any external protocol references used during implementation.
