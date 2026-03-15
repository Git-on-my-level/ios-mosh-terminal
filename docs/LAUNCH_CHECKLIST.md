# Launch Checklist — MVP Release

This checklist captures the non-code items required to ship a TestFlight/App Store build.

---

## Prerequisites

### Developer Account & Signing

- [ ] **Apple Developer Program membership** is active
- [ ] **Bundle ID** reserved in App Store Connect: `com.scalingforever.MoshTerminal`
- [ ] **Code signing certificates**:
  - Distribution certificate installed (not development/Ad Hoc)
  - Valid provisioning profile for the bundle ID
- [ ] **Team** selected correctly in Xcode project settings

### Version Numbers

Current version configuration in `MoshTerminal.xcodeproj`:

- **MARKETING_VERSION**: `1.0` (displayed in App Store)
- **CURRENT_PROJECT_VERSION**: `1` (build number; increment for each submission)

Update build number for new submissions:
```bash
# Increment build number (Xcode does this automatically on archive)
xcodebuild -project MoshTerminal.xcodeproj -target MoshTerminal -showBuildSettings | grep CURRENT_PROJECT_VERSION
```

---

## App Store Connect Metadata

### Required URLs & Contact

Prepare the following before submitting:

- [ ] **Support URL** (required): A public-facing URL where users can get support
  - Examples: GitHub Issues page, personal website, or contact form
  - Recommendation: Use a dedicated support page (or a public issues tracker). Avoid linking to private repos.
- [ ] **Privacy Policy URL** (required if app collects data): Not required for MVP (see `docs/PRIVACY_AND_EXPORT_COMPLIANCE.md`)
  - If you create one, ensure it states "no data collection"
- [ ] **Contact Email** (required): Email address for Apple/Apple Review to contact you
  - Use a monitored email address associated with your Apple Developer account

### App Information

- [ ] **Name**: "Mosh Terminal" (or your chosen app name)
- [ ] **Subtitle**: Short, descriptive tagline (e.g., "Reliable Mosh terminal client")
- [ ] **Description**: Brief description of what the app does
- [ ] **Keywords**: Relevant terms for App Store search (e.g., "mosh", "ssh", "terminal", "tmux")
- [ ] **Screenshots**: At least one required (6.5" or 6.7" iPhone recommended)
  - Note: This ticket does not cover creating marketing assets

### Age Rating

The app should be rated **4+** (Made for Ages 4+) because:
- No violence, profanity, or mature content
- No user-generated content
- No gambling, gambling-like content
- No unrestricted web access

---

## Export Compliance & Encryption

This app uses encryption for terminal emulation. The answers below are documented in `docs/PRIVACY_AND_EXPORT_COMPLIANCE.md`.

### App Store Connect Export Compliance Questions

- [ ] **Does your app contain encryption?** → **Yes**
- [ ] **Does your app qualify for any exemptions provided by Category 5, Part 2?** → **Yes**
- [ ] **Select exemption that applies** → **5D002(c)(1)** and **5D002(c)(2)**
  - Client-side terminal emulator using SSH and Mosh protocols
  - No key recovery/management features
  - Standard encryption for legitimate terminal access
- [ ] **Is your app made available to countries subject to U.S. trade sanctions?** → **No**
- [ ] **Is your app designed for use with a third-party app that may collect data?** → **No**

### Privacy Manifest

- [ ] `PrivacyInfo.xcprivacy` is included in the app bundle (see `docs/PRIVACY_AND_EXPORT_COMPLIANCE.md`)
- [ ] Required reason APIs are declared (UserDefaults `CA92.1`, System Boot Time `35F9.1`); no other privacy-sensitive APIs are used
- [ ] `NSLocalNetworkUsageDescription` is present in `Info.plist`
- [ ] Privacy questionnaire answers:
  - **Data Used to Track You**: None
  - **Data Linked to You**: None
  - **Data Not Linked to You**: None

---

## Build & Archive

### Pre-Build Checklist

- [ ] All frameworks are built: `./scripts/build_xcframeworks.sh`
- [ ] CI passes all tests: `./scripts/test_sim.sh`
- [ ] Version numbers are correct in `MoshTerminal.xcodeproj`
- [ ] Build configuration is set to **Release**
- [ ] Code signing is configured for **Distribution**

### Archive Creation

Run the archive script:
```bash
./scripts/archive_release.sh
```

Verify:
- [ ] Archive created successfully at `build/MoshTerminal.xcarchive`
- [ ] No build warnings or errors
- [ ] Code signing is valid (check organizer in Xcode)

---

## Pre-Flight QA

Before submitting to TestFlight, perform a **quick QA run** on a physical device:

- [ ] **Build + Smoke** (from `docs/QA_V1.md`):
  - [ ] App launches to Hosts list without crashes
  - [ ] Settings opens and shows all sections
  - [ ] Licenses screen displays correctly
- [ ] **Core Functionality** (from `docs/QA_V1.md`):
  - [ ] Add host + import key + connect to a Linux host with `mosh-server`
  - [ ] Start `tmux`, run `vim`, rotate device; rendering remains correct
  - [ ] Background app ~30s, return; reconnects automatically
  - [ ] Switch Wi-Fi ↔ cellular; reconnect succeeds
  - [ ] Host key change blocks connection with clear warning
  - [ ] UDP blocked shows actionable explanation
- [ ] **Version Display**:
  - [ ] Open Settings → About
  - [ ] Verify version (1.0) and build number (1) are displayed correctly

---

## TestFlight Distribution

### Internal Testing

- [ ] Upload archive to App Store Connect via Xcode Organizer or Transporter
- [ ] Wait for processing to complete
- [ ] Add yourself (or internal testers) to **Internal Testing** group
- [ ] Distribute build to testers
- [ ] Install on test devices and verify core functionality
- [ ] Check crash reports (if any) in App Store Connect

### External (Beta) Testing (Optional)

- [ ] Create **External Testing** group
- [ ] Add email addresses of external testers
- [ ] Provide test instructions (e.g., `docs/QA_V1.md` checklist)
- [ ] Monitor feedback and fix critical issues

### TestFlight Notes

When distributing to TestFlight, include:
- **What's New**: Brief description of changes (e.g., "Initial TestFlight release - Mosh terminal client")
- **Testing Instructions**: Reference `docs/QA_V1.md` for core scenarios
- **Known Issues**: List any known bugs or limitations (e.g., "No scrollback history - use tmux")

---

## App Store Review Submission

### Final Checklist

Before submitting for review:

- [ ] All metadata is complete (name, subtitle, description, keywords, screenshots)
- [ ] Export compliance questions are answered correctly
- [ ] Privacy questionnaire is answered (no data collection)
- [ ] Support URL and contact email are valid and accessible
- [ ] Build has been tested on at least one physical device
- [ ] No critical bugs remain in TestFlight feedback

### Submission Tips

- **Review Notes**: Briefly explain the app's purpose and value
  - Example: "Mosh Terminal is a minimal iOS client for Mosh, designed for reliable tmux sessions on flaky networks. It uses SSH for bootstrapping and Mosh for connectivity."
- **Demo Account**: Not required (app works with user's own servers)
- **Contact Info**: Provide a reachable email for Apple Review team

---

## Post-Release

### Monitor After Launch

- [ ] Check **App Store Connect** for review status
- [ ] Monitor **Crash Reports** and **Metrics** in App Store Connect
- [ ] Respond to **Reviews** and **Feedback** promptly
- [ ] Triage **Issues** from GitHub or TestFlight feedback

### Version Bumping

For subsequent releases:

- [ ] Update **MARKETING_VERSION** for major/minor changes (e.g., 1.0 → 1.1 → 2.0)
- [ ] Update **CURRENT_PROJECT_VERSION** (build number) for every submission
- [ ] Update "What's New" in App Store Connect with release notes

---

## References

- **Build Process**: `docs/RELEASE_BUILD.md`
- **QA Checklist**: `docs/QA_V1.md`
- **Privacy & Export Compliance**: `docs/PRIVACY_AND_EXPORT_COMPLIANCE.md`
- **Product Specification**: `SPEC_V1.md`
- **App Store Connect Help**: https://help.apple.com/app-store-connect/
