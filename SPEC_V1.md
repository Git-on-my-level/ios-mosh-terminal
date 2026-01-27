# Product Specification — iOS Mosh Client (v1)

## 0. Summary
A minimal iOS-native client that:
- Saves host profiles
- Imports SSH private keys
- Bootstraps `mosh-server` over SSH
- Runs a Mosh session over UDP
- Reconnects reliably on app foreground + network changes
- Provides a tmux-friendly terminal + keyboard row
- Offers a few global settings (font size, theme, keep-awake)

This is intentionally *not* a full-featured terminal / SSH suite.

---

## 1. Target user
People who live in `tmux` and want a dependable mobile Mosh experience on flaky networks.

---

## 2. Platforms and constraints
- Minimum OS: iOS/iPadOS **17.0+**
- iPhone + iPad supported
- Portrait + landscape supported
- External hardware keyboard supported
- Background execution: **not guaranteed**; treat backgrounding as disconnect and rely on reconnect

---

## 3. Goals (v1)
1. **Mosh-first:** Connect to a host via Mosh with key-based SSH bootstrap.
2. **Fast recovery:** Automatic reconnect when returning to the app and after network changes.
3. **tmux-friendly input:** Esc/Ctrl/Tab convenience and correct resize behavior.
4. **Minimal UI:** Host list → terminal, plus simple settings.
5. **Security:** Keychain for keys, TOFU host-key verification, no secret logging.

---

## 4. Non-goals (explicitly out of scope for v1)
- SSH-only sessions
- Jump hosts / bastions / ProxyCommand
- Port forwarding, X11 forwarding
- SFTP/SCP / file browser
- Multi-tab or split-pane UI
- Scrollback UX, search, selection tools (beyond basic iOS text input/paste)
- In-app key generation, agent forwarding, PKI management
- Password authentication for SSH (private-key auth only; passphrase for decrypting the private key is allowed)
- Scripting, plugins, local shells, “run arbitrary binaries”
- Cloud sync, accounts, subscriptions, telemetry

---

## 5. UX surface (screens)

### 5.1 Hosts list (default)
- List saved hosts with:
  - Display name (or hostname)
  - Username
  - Last connected timestamp
  - Status badge (connected / reconnecting / disconnected / failed)
- Actions:
  - Add host
  - Edit host
  - Delete host
  - Tap host to connect

### 5.2 Host editor
Fields:
- Display name (optional)
- Hostname (required)
- Username (required)
- SSH port (default 22)
- SSH key (required):
  - Choose from existing imported keys
  - Import from Files or Paste (OpenSSH private key formats)

### 5.3 Terminal
- Full-screen terminal view
- Visible connection state (small status area)
- Back to hosts list
- “Disconnect” action (stops reconnect attempts + engine)

### 5.4 Settings
Global only:
- Font size
- Theme: follow system / light / dark
- Keep screen awake (on/off)
- About / licenses

---

## 6. Connection behavior

### 6.1 Host key verification (TOFU)
- On first SSH connect to a (hostname, port):
  - Fetch server host key fingerprint
  - Display fingerprint and ask user to Trust / Cancel
  - Store trusted fingerprint
- On subsequent connects:
  - If fingerprint differs: hard fail with an explicit “Host key changed” error

### 6.2 Bootstrap flow
- Connect via SSH using selected private key
- Execute `mosh-server` in a way that yields a line like:
  - `MOSH CONNECT <udpPort> <base64Key>`
- Parse UDP port and session key
- Close SSH connection after bootstrap
- Start Mosh engine over UDP to the server IP/hostname + udpPort using the session key

### 6.3 Reconnect behavior
- Trigger reconnect when:
  - App enters foreground
  - Network path changes to “satisfied”
- Reconnect strategy:
  1. Attempt to resume current UDP session (if the app is still alive and has session params in memory)
  2. If that fails quickly, re-bootstrap via SSH (start a new `mosh-server`) and reconnect
- Reconnect must be **idempotent** (repeated triggers do not spawn overlapping attempts).
- Use bounded backoff; provide cancellation.

### 6.4 Backgrounding behavior
- When app enters background:
  - Stop/park the Mosh engine promptly
  - Update UI state to disconnected
- Do not attempt background keepalive.

### 6.5 UDP-blocked / unreachable networks
If SSH bootstrap succeeds but UDP cannot establish:
- Show a clear error:
  - “This network appears to block UDP. Mosh requires UDP.”
- Provide actions:
  - Retry
  - Back to hosts list

---

## 7. Terminal requirements (v1)
- Baseline xterm/VT100 behavior sufficient for shells + `tmux`
- UTF-8 support
- 256-color support
- Correct handling of:
  - Cursor movement
  - Line wrap
  - Alternate screen apps (vim, less)
  - Resize events (on orientation changes + keyboard show/hide)
- No promise of scrollback; users should use `tmux` history on the remote side.

---

## 8. Input requirements (v1)
- On-screen accessory row includes:
  - Esc, Ctrl (sticky toggle), Tab, `|`, `-`, `/`, `:`
- Hardware keyboard supported (including modifiers)
- Paste into terminal supported

---

## 9. Data and storage
- Host profiles: stored as a versioned JSON file in Application Support
- Trusted host keys: stored locally (versioned) and matched by (hostname, port)
- Private keys: stored in Keychain; Host profile stores a reference ID only
- Mosh session key: **in-memory only** (do not persist to disk)

---

## 10. Privacy & security
- No analytics, tracking, or third-party network calls
- Redact secrets in all logs
- Keys stored with device-only Keychain accessibility where practical

---

## 11. Licensing note (engineering requirement)
Upstream Mosh is GPL-licensed; if you ship it embedded you must comply with GPL obligations.  
Ticket 002 requires confirming the licensing/compliance plan and documenting it before deeper integration.

---

## 12. Acceptance checklist (manual)
A v1 build is acceptable when all items below pass on real devices:
1. Add host + import key + connect to a Linux host with `mosh-server` installed.
2. Start `tmux`, run `vim`, resize by rotating device; rendering remains correct.
3. Put app in background for ~30s, return; app reconnects without manual re-entry.
4. Switch Wi‑Fi ↔ cellular (or simulate network change), return; reconnect succeeds.
5. If host key changes, connection is blocked with a clear warning.
6. If UDP is blocked, user sees an actionable explanation.
