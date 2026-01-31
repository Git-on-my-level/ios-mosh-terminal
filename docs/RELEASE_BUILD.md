# Release Build Guide

This document describes how to build and archive MoshTerminal for distribution (TestFlight/App Store).

## Prerequisites

- Xcode with valid Apple Developer account
- Code signing certificates and provisioning profiles configured
- Required frameworks built: `./scripts/build_xcframeworks.sh`

## Build for Distribution (Device)

### Archive

Run the archive script to create a signed `.xcarchive`:

```bash
./scripts/archive_release.sh
```

By default, the archive is created at `build/MoshTerminal.xcarchive`. Override with:

```bash
ARCHIVE_PATH="build/Custom.xcarchive" ./scripts/archive_release.sh
```

### Export IPA (Optional)

If you need an `.ipa` file (e.g., for ad-hoc distribution), use Xcode's export options:

```bash
xcodebuild -exportArchive \
  -archivePath build/MoshTerminal.xcarchive \
  -exportPath build/export \
  -exportOptionsPlist ExportOptions.plist
```

Create an `ExportOptions.plist` that matches your distribution needs (App Store, Ad Hoc, etc.).

## Release Simulator Build

To verify Release configuration works on simulator:

```bash
CONFIGURATION=Release ./scripts/build_sim.sh
```

## CI

CI automatically builds both Debug and Release configurations for the simulator to catch compiler/linker issues. Signed archives are not performed in CI.
