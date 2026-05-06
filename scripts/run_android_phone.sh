#!/bin/zsh

set -euo pipefail

ADB_BIN="${ADB_BIN:-$HOME/Library/Android/sdk/platform-tools/adb}"
device_id="${1:-${ANDROID_DEVICE_ID:-}}"

if [[ ! -x "$ADB_BIN" ]]; then
  echo "adb not found: $ADB_BIN" >&2
  exit 1
fi

if [[ -z "$device_id" ]]; then
  device_id="$("$ADB_BIN" devices | awk 'NR > 1 && $2 == "device" && $1 !~ /^emulator-/ { print $1; exit }')"
fi

if [[ -z "$device_id" ]]; then
  echo "No physical Android device found." >&2
  exit 1
fi

echo "Using Android phone: $device_id"
echo "Applying adb reverse: tcp:8000 -> tcp:8000"
"$ADB_BIN" -s "$device_id" reverse tcp:8000 tcp:8000
echo "adb reverse ready for $device_id"
