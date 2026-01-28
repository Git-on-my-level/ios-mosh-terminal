#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORKS_DIR="$ROOT_DIR/Frameworks"

required_frameworks=(
  "$FRAMEWORKS_DIR/libcrypto.xcframework"
  "$FRAMEWORKS_DIR/libssl.xcframework"
  "$FRAMEWORKS_DIR/libssh2.xcframework"
)

missing=0
for framework in "${required_frameworks[@]}"; do
  if [ ! -d "$framework" ]; then
    echo "Missing required framework: $framework" >&2
    missing=1
  fi
done

if [ "$missing" -ne 0 ]; then
  echo "Run scripts/build_xcframeworks.sh to build dependencies." >&2
  exit 1
fi

"$ROOT_DIR/scripts/build_sim.sh"
"$ROOT_DIR/scripts/test_sim.sh"
