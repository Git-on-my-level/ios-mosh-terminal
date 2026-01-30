#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HARNESS_SCRIPT="$ROOT_DIR/scripts/mosh_harness.sh"
STATE_FILE=${MOSH_HARNESS_STATE_FILE:-/tmp/mosh-harness.state}
DESTINATION=${DESTINATION:-"platform=iOS Simulator,name=iPhone 17 Pro"}
TEST_IDENTIFIER="MoshTerminalTests/MoshE2EIntegrationTests/testMoshBootstrapAndHandshake"

started_harness=0

ensure_harness() {
  local state_dir
  if [ -f "$STATE_FILE" ]; then
    state_dir=$(cat "$STATE_FILE")
    if [ -f "$state_dir/connection.env" ]; then
      echo "$state_dir/connection.env"
      return
    fi
  fi

  "$HARNESS_SCRIPT" start >&2
  started_harness=1
  state_dir=$(cat "$STATE_FILE")
  if [ ! -f "$state_dir/connection.env" ]; then
    echo "Failed to locate connection.env after starting harness." >&2
    exit 1
  fi
  echo "$state_dir/connection.env"
}

cleanup() {
  if [ "$started_harness" -eq 1 ]; then
    "$HARNESS_SCRIPT" stop
  fi
}
trap cleanup EXIT

CONNECTION_ENV=$(ensure_harness)
# shellcheck source=/dev/null
source "$CONNECTION_ENV"

required_vars=(MOSH_HOST MOSH_SSH_PORT MOSH_USER MOSH_KEY_PATH)
for var in "${required_vars[@]}"; do
  if [ -z "${!var:-}" ]; then
    echo "Missing required env var: $var" >&2
    exit 1
  fi
done

if [ ! -f "$MOSH_KEY_PATH" ]; then
  echo "SSH key not found at: $MOSH_KEY_PATH" >&2
  exit 1
fi

xcodebuild \
  -project "$ROOT_DIR/MoshTerminal.xcodeproj" \
  -scheme "MoshTerminal" \
  -configuration Debug \
  -sdk iphonesimulator \
  -destination "$DESTINATION" \
  -only-testing:"$TEST_IDENTIFIER" \
  test
