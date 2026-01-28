# Engineering Constitution (iOS Mosh Client v1)

This constitution is binding for all implementation agents.  
If any other document conflicts with this one, **this document wins**.

## Article 1 — Ship v1, not “a terminal app”
The goal is a minimal, reliable, Mosh-first client that works well with `tmux`.  
Anything that does not directly support this is deferred.

## Article 2 — Mosh-first is non-negotiable
- The product offers **Mosh sessions**.
- SSH exists only to bootstrap `mosh-server` (authentication + startup), then the SSH connection ends.
- Do not implement SSH-only sessions, port forwarding, SFTP/SCP, jump hosts, or “general SSH client” features in v1.

## Article 3 — Reconnect reliability beats everything
- “One-tap reconnect” and “auto-reconnect on foreground/network change” are core behavior.
- State must be explicit: connected / reconnecting / disconnected / failed.
- Failures must be explainable and actionable (no vague “something went wrong”).

## Article 4 — iOS constraints are reality, not bugs
- Do **not** promise persistent background connections.
- Assume the app will be suspended; design for rapid recovery on foreground.
- Battery and thermal limits matter more than theoretical uptime.

## Article 5 — Scope discipline is enforced
If it is not in `SPEC_V1.md`, it is out of scope for v1.  
If a change is required, create a new ticket and update the spec explicitly.

## Article 6 — Secure by default
- Private keys must be stored in the iOS Keychain (device-only where possible).
- Implement TOFU host-key verification (store and verify server host key fingerprint).
- Never log secrets (private keys, passphrases, session keys).
- No analytics, no tracking, no third-party network calls.

## Article 7 — Opinionated UX, minimal settings
- Global settings only. No theme editors, no per-host profiles explosion.
- Prefer sensible defaults over configurability.
- Avoid modal spam; only block the user when they cannot proceed.

## Article 8 — Maintainable architecture over clever hacks
- Strict separation between: UI, persistence, SSH bootstrap, Mosh engine, terminal rendering.
- All long-running work is cancellable.
- Keep interfaces mockable; write tests for critical logic (persistence, parsing, state machine).

## Article 9 — Compliance is part of engineering
- Track third-party licenses and include required attributions.
- Avoid dynamic code execution and “plugin systems” in v1.
- If using GPL components, comply fully (source offer/availability, notices).

## Article 10 — Clean-room Mosh engine (App Store–safe)
- GPL-licensed Mosh client code MUST NOT be embedded, linked, or included in the app.
- v1 SHALL use a clean-room or permissively licensed Mosh protocol implementation.
- This is a binding architectural decision; conflicting tickets or code must be rejected.
