#!/usr/bin/env bash
set -euo pipefail

# This script copies the PrivacyInfo.xcprivacy file to the built app bundle.
# It should be run after building the app.

APP_PATH="${1:-./build/Debug-iphonesimulator/MoshTerminal.app}"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App bundle not found at $APP_PATH"
    echo "Usage: $0 [path-to-app-bundle]"
    exit 1
fi

cp MoshTerminal/PrivacyInfo.xcprivacy "$APP_PATH/PrivacyInfo.xcprivacy"
echo "PrivacyInfo.xcprivacy copied to $APP_PATH"
