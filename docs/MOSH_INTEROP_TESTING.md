# Mosh Interop Testing (Manual)

This checklist helps validate interoperability against a real `mosh-server` on an actual network.

## 1) Install mosh-server on a Linux host

Choose one of the following on the server:

- Debian/Ubuntu:
  - `sudo apt-get update`
  - `sudo apt-get install mosh`
- Fedora/RHEL:
  - `sudo dnf install mosh` (or `sudo yum install mosh`)
- Arch:
  - `sudo pacman -S mosh`

Confirm the binary:
`mosh-server --version`

## 2) Firewall and network requirements

Mosh uses:
- SSH (TCP 22 by default) for bootstrap
- UDP for the data channel

The UDP port is negotiated on connect. By default, most servers select from **60000–61000**.
Make sure inbound UDP is allowed for that range (or the specific port shown in the bootstrap line).

If you run a stateful firewall, allow established/related UDP or add a rule for the negotiated port.

## 3) Read the bootstrap line

`mosh-server` prints a line like:

`MOSH CONNECT <udpPort> <base64Key>`

- `<udpPort>` is the UDP port to reach on the server
- `<base64Key>` is the session key (do not log or share it)

If you want to see it directly, SSH into the server and run:
`mosh-server`
Then copy the `MOSH CONNECT ...` line for reference.

## 4) Troubleshooting checklist

- **No UDP traffic / immediate disconnect**
  - UDP blocked by firewall or network policy.
  - Confirm UDP port range is open on the server.
- **Connects on Wi‑Fi, fails on cellular**
  - Carrier‑grade NAT or UDP blocked by carrier.
  - Try a different network or VPN that allows UDP.
- **Frequent reconnects / drops**
  - Unstable network path; confirm the app is not backgrounded.
  - Verify no packet mangling devices in the path.
- **SSH succeeds but no terminal output**
  - UDP port blocked or NAT mapping expiring too quickly.
  - Verify that `mosh-server` is running on the host.

## 5) Manual acceptance script

Run these steps in order, observing the in‑app debug overlay when enabled.

1. Connect to the host.
2. Confirm keystrokes appear on the server (`whoami`, `ls`, etc.).
3. Start `tmux`, then run `vim` inside it.
4. Rotate the device to force a resize; confirm the remote app resizes.
5. Toggle Wi‑Fi off/on or switch to cellular and back.
6. Background the app for ~10 seconds, then foreground.

Success criteria:
- Keystrokes reach the server.
- Host output updates correctly.
- Reconnect behavior engages when roaming or returning from background.
