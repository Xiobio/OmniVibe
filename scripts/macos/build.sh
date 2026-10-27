#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
package_root="$repo_root/src/OmniVibeMac"
configuration="${CONFIGURATION:-debug}"
case "$configuration" in debug|release) ;; *) echo 'CONFIGURATION must be debug or release.' >&2; exit 2 ;; esac

swift build --package-path "$package_root" -c "$configuration"
binary_root="$(swift build --package-path "$package_root" -c "$configuration" --show-bin-path)"
output_root="${OMNIVIBE_OUTPUT_DIR:-$repo_root/artifacts/macos}"
app="$output_root/OmniVibe.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"
cp "$package_root/Packaging/Info.plist" "$app/Contents/Info.plist"
cp "$binary_root/OmniVibeMac" "$app/Contents/MacOS/OmniVibeMac"
fixture_app="$app/Contents/Helpers/OmniVibeFixture.app"
mkdir -p "$fixture_app/Contents/MacOS"
cp "$binary_root/OmniVibeFixture" "$fixture_app/Contents/MacOS/OmniVibeFixture"
cp "$package_root/Packaging/Fixture-Info.plist" "$fixture_app/Contents/Info.plist"
focus_fixture_app="$app/Contents/Helpers/OmniVibeFocusFixture.app"
mkdir -p "$focus_fixture_app/Contents/MacOS"
cp "$binary_root/OmniVibeFixture" "$focus_fixture_app/Contents/MacOS/OmniVibeFixture"
cp "$package_root/Packaging/FocusFixture-Info.plist" "$focus_fixture_app/Contents/Info.plist"
# Remove the obsolete, generated helper from earlier local preview builds.
if [[ -f "$app/Contents/Helpers/OmniVibeFixture" ]]; then rm "$app/Contents/Helpers/OmniVibeFixture"; fi
cp "$repo_root/LICENSE" "$repo_root/THIRD_PARTY_NOTICES.md" "$app/Contents/Resources/"
ditto "$package_root/Sources/OmniVibeMac/Resources/Localization" "$app/Contents/Resources/Localization"
cp "$repo_root/assets/brand/v4/icons/omnivibe-128.png" "$app/Contents/Resources/omnivibe-128.png"

# Reuse the original Windows artwork and catalogues for the macOS presentation.
skin_resources="$app/Contents/Resources/skins"
mkdir -p "$skin_resources/loadouts"
cp "$repo_root/skins/catalog.json" "$skin_resources/catalog.json"
ditto "$repo_root/skins/identities" "$skin_resources/identities"
ditto "$repo_root/skins/native-v2" "$skin_resources/native-v2"
ditto "$repo_root/skins/loadouts/suites-v1" "$skin_resources/loadouts/suites-v1"
ditto "$repo_root/skins/audio" "$skin_resources/audio"
mkdir -p "$skin_resources/signature-audio"
cp "$repo_root/skins/signature-audio/catalog.json" "$repo_root/skins/signature-audio/README.md" "$skin_resources/signature-audio/"
ditto "$repo_root/skins/signature-audio/bundled" "$skin_resources/signature-audio/bundled"
ditto "$repo_root/skins/completion-audio" "$skin_resources/completion-audio"
for skin_dir in "$repo_root"/skins/*; do
    if [[ -f "$skin_dir/illustration.png" ]]; then
        skin_slug="$(basename "$skin_dir")"
        mkdir -p "$skin_resources/$skin_slug"
        cp "$skin_dir/illustration.png" "$skin_resources/$skin_slug/illustration.png"
    fi
done

# Full native Terminal profiles reuse the calibrated 20-color manifest and the
# original precomposed backgrounds. GIF resources remain available as assets;
# the native Terminal adapter never claims animated background playback.
terminal_resources="$app/Contents/Resources/themes/windows-terminal"
mkdir -p "$terminal_resources/assets/refined-v1"
cp "$repo_root/themes/windows-terminal/skins.json" "$terminal_resources/skins.json"
for terminal_slug in ink-jade midnight cinnabar hextech tactical protocol adventure arsenal relic starlight formation astral wonderland; do
    for terminal_suffix in c-v1.png frame-only-v1.png c-v1.gif frame-only-v1.gif; do
        cp "$repo_root/themes/windows-terminal/assets/refined-v1/$terminal_slug-$terminal_suffix" "$terminal_resources/assets/refined-v1/"
    done
done

iconset="$output_root/OmniVibe.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    cp "$repo_root/assets/brand/v4/icons/omnivibe-$size.png" "$iconset/icon_${size}x${size}.png"
    double=$((size * 2))
    cp "$repo_root/assets/brand/v4/icons/omnivibe-$double.png" "$iconset/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/OmniVibe.icns"
plutil -lint "$app/Contents/Info.plist"
# A development certificate gives successive builds a stable designated
# requirement. Ad-hoc code is identified by its changing hash, which can leave
# an old Accessibility toggle enabled while the rebuilt app is denied access.
signing_identity="${OMNIVIBE_SIGN_IDENTITY:-}"
if [[ -z "$signing_identity" ]]; then
    signing_candidates="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    signing_identity="$(printf '%s\n' "$signing_candidates" | awk '/"Apple Development:|"Developer ID Application:/ { print $2; exit }')"
fi
if [[ -z "$signing_identity" ]]; then
    signing_identity="-"
    printf '\nNo development signing certificate found; Accessibility may need renewed permission after rebuilding.\n'
fi
# Development signing is still a local preview, not a notarized public release.
codesign --force --sign "$signing_identity" --timestamp=none "$fixture_app"
codesign --force --sign "$signing_identity" --timestamp=none "$focus_fixture_app"
codesign --force --sign "$signing_identity" --timestamp=none "$app"
codesign --verify --deep --strict "$app"
printf '\nBuilt local macOS preview: %s\n' "$app"
