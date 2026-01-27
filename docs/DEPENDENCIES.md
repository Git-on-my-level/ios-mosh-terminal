# Dependencies (v1 plan)

This document freezes the dependency approach for v1 and captures licensing/compliance requirements.

## Summary

- Terminal emulator: **SwiftTerm** (Swift package).
- SSH transport: **libssh2** wrapped as an XCFramework.
- Crypto: **OpenSSL** (libcrypto/libssl) as an XCFramework dependency for libssh2.
- Mosh engine: **embed upstream Mosh client** as an XCFramework (GPL-3.0).
  - Alternative (non-goal for v1): independent protocol implementation.

## Dependency Matrix

| Dependency | Purpose | License | Integration | Notes |
| --- | --- | --- | --- | --- |
| SwiftTerm | Terminal emulator + VT100 parsing | MIT | SPM | Used to render terminal UI. |
| libssh2 | SSH transport for key-based bootstrap | BSD 3-Clause | XCFramework | C library; wrapper module in app target. |
| OpenSSL | Crypto backend for libssh2 | Apache-2.0 | XCFramework | Required by libssh2 build. |
| Mosh (client) | Mosh protocol + state sync | GPL-3.0-only | XCFramework | Upstream client code embedded for v1. |

## Mosh Engine Decision

**Chosen for v1:** Embed the upstream Mosh client code (Option A). This is the fastest path to a working Mosh-first client.

**Implications:** Mosh is GPL-3.0-only; shipping a binary that links Mosh requires GPL compliance for the app as a whole. This must be reviewed and accepted by legal/product before release.

**Non-goal for v1:** Re-implementing the Mosh protocol (Option B). If GPL constraints are unacceptable, v1 must be delayed or the dependency strategy must change.

## Compliance Checklist (v1)

- Include third-party license texts in the app (`About → Licenses`) and in the repo (`LICENSES/` or similar).
- Provide attribution for MIT/BSD/Apache dependencies.
- If Mosh (GPL-3.0) is linked:
  - Ensure the app is distributed under GPL-3.0-compatible terms.
  - Provide source code (or a written offer) for the full app + any modifications to Mosh.
  - Ensure build scripts and dependency sources are available to recipients.

## Integration Approach

### SwiftTerm (SPM)
- Add SwiftTerm via Swift Package Manager and link it to the app target.

### libssh2 + OpenSSL (XCFramework)
- Build static XCFrameworks for libssh2 and OpenSSL and vendor under `Frameworks/`.
- Provide a thin Swift wrapper module for session/channel management.
- Build pipeline stub lives at `scripts/build_xcframeworks.sh`.

### Mosh (XCFramework)
- Build an XCFramework from the upstream Mosh client sources.
- Expose a minimal Objective-C/Swift bridging layer for session control and I/O.
- Use the same build pipeline stub as above.

## Deferred Items

- Exact version pinning (to be decided when integrations begin).
- Legal review of GPL requirements prior to release.
- `About → Licenses` population automation.
