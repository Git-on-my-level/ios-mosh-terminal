# Privacy and Export Compliance

This document captures privacy and export compliance information for App Store submission.

## Data Collection

**The app does not collect any user data.**

All data remains on-device:
- SSH host configurations are stored locally in the app's container
- SSH private keys are stored in the iOS Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (device-only, unlocked-only)
- Terminal session data is not logged or transmitted to any third-party servers
- Optional in-app tips are processed by Apple (StoreKit); the app does not log or transmit purchase events
- No analytics or crash reporting is included

## Third-Party SDKs

The app includes the following third-party libraries:

| Library | Purpose | License | Data Collection |
|---------|---------|---------|-----------------|
| SwiftTerm | Terminal emulator (VT100 parsing/rendering) | MIT | None |
| libssh2 | SSH client for key-based authentication | BSD 3-Clause | None |
| OpenSSL | Crypto backend for libssh2 | Apache-2.0 | None |
| MoshEngine (clean-room) | Mosh protocol implementation + state sync | MIT/BSD/Apache | None |
| Network.framework (Apple) | UDP transport for Mosh | Apple Platform License | N/A |
| CryptoKit (Apple) | AEAD/crypto primitives | Apple Platform License | N/A |

**Note:** All third-party dependencies are privacy-compliant and do not collect user data.

## Encryption and Export Compliance

### Encryption Usage

This app uses encryption for legitimate terminal emulation purposes:

- **SSH transport** (libssh2 + OpenSSL): Encrypted connections to remote servers
- **Mosh protocol** (MoshEngine + CryptoKit): Encrypted UDP-based remote shell sessions

### Export Compliance Checklist

When submitting to App Store Connect, the following answers apply to export compliance questions:

| Question | Answer |
|----------|--------|
| Does your app contain encryption? | **Yes** |
| Does your app qualify for any exemptions provided by Category 5, Part 2 of the U.S. Export Administration Regulations? | **Yes** |
| Select the exemption that applies | `5D002(c)(1)` - "Software that provides for 'authentication' or 'digital signature' and does not provide for key recovery or management" and `5D002(c)(2)` - "Software that is specially designed for performing 'cryptographic processing' used for the protection of information transmitted over 'public networks'" |
| Is your app made available to customers in countries subject to U.S. trade sanctions? | **No** |
| Is your app designed for use with a third-party app that may collect data? | **No** |

**Rationale:** This terminal emulator app is exempt from encryption registration requirements under EAR Category 5, Part 2 because it is a client-side application that uses standard SSH and Mosh protocols for legitimate terminal access. The app does not provide key recovery/management features and does not enable or facilitate circumvention of encryption controls.

### App Store Connect Privacy Answers

When submitting the app, use the following responses for the privacy questionnaire:

- **Data Used to Track You**: None
- **Data Linked to You**: None
- **Data Not Linked to You**: None

### Additional Notes

- The app does not use privacy-sensitive APIs like Contacts, Location, Photos, Camera, or Microphone
- A `PrivacyInfo.xcprivacy` file is included in the app bundle declaring required-reason API usage:
  - `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`) for on-device app settings
  - `NSPrivacyAccessedAPICategorySystemBootTime` (`35F9.1`) for monotonic timers/elapsed-time calculations
- All keys and sensitive data are stored using iOS secure storage mechanisms (Keychain)
- The app requires full network access for SSH and Mosh connections but does not track or monetize user activity
- The app includes `NSLocalNetworkUsageDescription` because users may connect to servers on the local network

## References

- [Apple Privacy Manifest Documentation](https://developer.apple.com/documentation/bundleresources/privacy_manifest_files)
- [U.S. Export Administration Regulations (EAR) - Category 5](https://www.ecfr.gov/current/title-15/subtitle-B/chapter-VII/subchapter-C/part-742)
- [App Store Connect Encryption Information](https://help.apple.com/app-store-connect/#/dev88bc5c8c5)
