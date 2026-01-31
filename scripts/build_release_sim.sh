#!/usr/bin/env bash
set -euo pipefail

CONFIGURATION=Release ./scripts/build_sim.sh "$@"
