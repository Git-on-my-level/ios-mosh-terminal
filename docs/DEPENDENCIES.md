# Dependencies (v1 plan)

This document freezes the dependency approach for v1 and captures licensing/compliance requirements.

## Summary

- Terminal emulator: **SwiftTerm** (Swift package).
- SSH transport: **libssh2** wrapped as an XCFramework.
- Crypto: **OpenSSL** (libcrypto/libssl) as an XCFramework dependency for libssh2.
- Mosh engine: **in-house clean-room MoshEngine** (Swift/C) under a permissive license.
- UDP transport: **Network.framework** (Apple platform framework).
- Mosh crypto: **CryptoKit** (Apple) or a permissively licensed library if required.
- Upstream Mosh GPL code is **not used**.

## Dependency Matrix

| Dependency | Purpose | License | Integration | Notes |
| --- | --- | --- | --- | --- |
| SwiftTerm | Terminal emulator + VT100 parsing | MIT | SPM | Used to render terminal UI. |
| libssh2 | SSH transport for key-based bootstrap | BSD 3-Clause | XCFramework | C library; wrapper module in app target. |
| OpenSSL | Crypto backend for libssh2 | Apache-2.0 | XCFramework | Required by libssh2 build. |
| MoshEngine (clean-room) | Mosh protocol + state sync | MIT/BSD/Apache | In-repo module | Clean-room implementation, App Store–safe. |
| Network.framework | UDP transport | Apple Platform | System framework | Used by MoshEngine for UDP. |
| CryptoKit | AEAD/crypto primitives for MoshEngine | Apple Platform | System framework | Replace only if requirements exceed CryptoKit. |

## Mosh Engine Decision

**Chosen for v1:** Implement a clean-room, permissively licensed Mosh protocol client (MoshEngine).

**Implications:** The app must not embed, link, or include upstream GPL Mosh client code. Only protocol behavior and public documentation are referenced.

## Compliance Checklist (v1)

- Include third-party license texts in the app (`About → Licenses`) and in the repo (`LICENSES/` or similar).
- Provide attribution for MIT/BSD/Apache dependencies.
- Do not add GPL dependencies without an explicit constitution change.

## Integration Approach

### SwiftTerm (SPM)
- Add SwiftTerm via Swift Package Manager and link it to the app target.

### libssh2 + OpenSSL (XCFramework)
- Build static XCFrameworks for libssh2 and OpenSSL and vendor under `Frameworks/`.
- Provide a thin Swift wrapper module for session/channel management.
- Build pipeline stub lives at `scripts/build_xcframeworks.sh`.

### MoshEngine (in-repo module)
- Implement a clean-room Mosh protocol client under a permissive license.
- Expose a minimal Swift interface for session control and I/O.
- Use Network.framework for UDP transport.

## Deferred Items

- Exact version pinning (to be decided when integrations begin).
- `About → Licenses` population automation.
