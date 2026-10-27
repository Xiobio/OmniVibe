#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
output_root="${OMNIVIBE_OUTPUT_DIR:-$repo_root/artifacts/macos}"
app_binary="$output_root/OmniVibe.app/Contents/MacOS/OmniVibeMac"
python3 "$repo_root/scripts/macos/localization-catalog.py" --check
swift test --package-path "$repo_root/src/OmniVibeMac" -c "${CONFIGURATION:-debug}"
OMNIVIBE_OUTPUT_DIR="$output_root" "$repo_root/scripts/macos/build.sh"
python3 "$repo_root/scripts/macos/check-agent-bridge.py" "$app_binary" | tee "$output_root/agent-bridge-results.json"
"$app_binary" --validate-appearance "$output_root/appearance-results.json"
if [[ "${1:-}" == "--desktop" ]]; then
    result_path="$output_root/desktop-smoke-results.json"
    "$app_binary" --smoke-test "$result_path"
    "$app_binary" --validate-arrangement "$output_root/arrangement-desktop-results.json"
fi
