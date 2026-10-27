#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
output_root="${OMNIVIBE_OUTPUT_DIR:-$repo_root/artifacts/macos}"
"$repo_root/scripts/macos/build.sh"
open "$output_root/OmniVibe.app" --args "$@"
