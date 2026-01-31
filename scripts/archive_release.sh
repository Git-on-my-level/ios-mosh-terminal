#!/usr/bin/env bash
set -euo pipefail

PROJECT="MoshTerminal.xcodeproj"
SCHEME="MoshTerminal"
ARCHIVE_PATH=${ARCHIVE_PATH:-"build/MoshTerminal.xcarchive"}

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  archive
