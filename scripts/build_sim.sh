#!/usr/bin/env bash
set -euo pipefail

PROJECT="MoshTerminal.xcodeproj"
SCHEME="MoshTerminal"
CONFIGURATION=${CONFIGURATION:-"Debug"}
DESTINATION=${DESTINATION:-"platform=iOS Simulator,name=iPhone 17 Pro"}

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphonesimulator \
  -destination "$DESTINATION" \
  build
