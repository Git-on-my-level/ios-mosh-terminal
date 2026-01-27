#!/usr/bin/env bash
set -euo pipefail

PROJECT="MoshTerminal.xcodeproj"
SCHEME="MoshTerminal"
DESTINATION=${DESTINATION:-"platform=iOS Simulator,name=iPhone 17 Pro"}

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "$DESTINATION" \
  build
