# Ticket 015 — App Store compliance: privacy manifest, local network, dependency bumps

## Goal
Make the app submission-ready for App Store privacy/compliance checks and reduce supply-chain risk by updating pinned crypto dependencies.

## Deliverables
- Privacy manifest (`PrivacyInfo.xcprivacy`) declares required-reason API usage:
  - `NSPrivacyAccessedAPICategoryUserDefaults` with reason `CA92.1`
  - `NSPrivacyAccessedAPICategorySystemBootTime` with reason `35F9.1`
- `Info.plist` includes `NSLocalNetworkUsageDescription`
- XCFramework pipeline pins and builds:
  - OpenSSL **3.0.19** (tag `openssl-3.0.19`)
  - libssh2 **1.11.1** (tag `libssh2-1.11.1`)
- Docs updated:
  - `docs/DEPENDENCIES.md`
  - `docs/PRIVACY_AND_EXPORT_COMPLIANCE.md`
  - `docs/LAUNCH_CHECKLIST.md`

## Acceptance criteria
- `./scripts/build_xcframeworks.sh` completes successfully
- `./scripts/build_sim.sh` succeeds with updated frameworks
- Manual App Store submission checklist reflects the new privacy manifest + local network key

## Notes
- Export compliance (encryption) still requires correct App Store Connect answers; see `docs/PRIVACY_AND_EXPORT_COMPLIANCE.md`.
