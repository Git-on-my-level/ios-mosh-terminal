#!/usr/bin/env bash
# Shared functions for iOS Simulator destination detection

# get_available_iphone_simulator
# Outputs a destination string for the newest available iPhone simulator
# Format: "platform=iOS Simulator,name=<device_name>"
# Exits with error if no iPhone simulator is available
get_available_iphone_simulator() {
    local device
    device=$(xcrun simctl list devices available | grep "iPhone" | grep -v "iPhone SE" | tail -1 | awk -F'[()]' '{print $1}' | xargs)

    if [ -z "$device" ]; then
        echo "Error: No available iPhone simulator found" >&2
        exit 1
    fi

    echo "platform=iOS Simulator,name=$device"
}
