#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
"$repo_root/scripts/macos/build.sh"
open "$repo_root/artifacts/macos/OmniVibe.app" --args "$@"
