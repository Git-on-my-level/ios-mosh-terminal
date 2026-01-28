# QA Checklist — v1

Use this checklist to validate a release candidate on a real device (iOS/iPadOS 17+). Record results per device.

## Build + Smoke
- [ ] App launches to Hosts list without crashes.
- [ ] Settings opens and shows Appearance, Session, Keys, About.
- [ ] Licenses screen lists SwiftTerm, libssh2, OpenSSL, Mosh with license text.
- [ ] App icon displays (placeholder is acceptable for v1).

## Hosts + Keys
- [ ] Add host with hostname, username, port, and selected key.
- [ ] Import OpenSSH private key from Files.
- [ ] Import OpenSSH private key via paste.
- [ ] Key list shows label + type + passphrase requirement.
- [ ] Edit host updates persisted values.
- [ ] Delete host removes it from the list and persistent store.

## Connection + Bootstrap
- [ ] First connect to new host prompts TOFU host key trust.
- [ ] Accepting host key stores fingerprint and connects.
- [ ] Rejecting host key blocks connection with a clear error.
- [ ] If host key changes, connection fails with "Host key changed" guidance.
- [ ] If `mosh-server` missing, error explains installation needed.
- [ ] If locale error, error explains UTF-8 locale requirement.

## Terminal Behavior
- [ ] Terminal opens full-screen and shows connection state banner.
- [ ] tmux session starts successfully.
- [ ] `vim` renders and accepts input.
- [ ] Orientation change triggers resize and layout remains correct.
- [ ] Accessory row keys (Esc, Ctrl, Tab, |, -, /, :) send correct input.
- [ ] Hardware keyboard works with modifiers and shortcuts.
- [ ] Paste works in terminal.

## Reconnect + Networking
- [ ] Background app for ~30s; return and reconnects automatically.
- [ ] Toggle Wi-Fi to cellular (or simulate path change); reconnect succeeds.
- [ ] Reconnect does not spawn overlapping attempts (no duplicated sessions).
- [ ] UDP blocked/unreachable shows actionable error and offers Retry/Back.

## Settings
- [ ] Font size changes terminal rendering.
- [ ] Theme mode follows selection (System/Light/Dark).
- [ ] Keep Awake prevents screen dimming while connected.

## Security + Privacy
- [ ] No secrets appear in error messages.
- [ ] Keys are stored in Keychain (device-only if available).
- [ ] Trusted host keys are stored locally and matched by host+port.

## Acceptance Checklist (SPEC_V1)
- [ ] Add host + import key + connect to a Linux host with `mosh-server` installed.
- [ ] Start tmux, run vim, rotate device; rendering remains correct.
- [ ] Background app ~30s, return; reconnects without manual re-entry.
- [ ] Switch Wi-Fi ↔ cellular (or simulate network change); reconnect succeeds.
- [ ] Host key change blocks connection with clear warning.
- [ ] UDP blocked shows actionable explanation.
