#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/simctl_helpers.sh"

PROJECT="MoshTerminal.xcodeproj"
SCHEME="MoshTerminal"
CONFIGURATION=${CONFIGURATION:-"Debug"}
DESTINATION=${DESTINATION:-$(get_available_iphone_simulator)}

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphonesimulator \
  -destination "$DESTINATION" \
  build
