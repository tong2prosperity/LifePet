#!/bin/bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <booted-simulator-uuid> [output-directory]" >&2
    exit 64
fi

simulator_id="$1"
output_directory="${2:-.tmp/animation-verification/simulator-states}"
bundle_id="fun.tiebao.co.Pibo"
states=(default weak pigu muscle tired angry dive boring coolhide sleep-1 sleep-2 awake)

if ! xcrun simctl list devices | grep -F "$simulator_id" | grep -q '(Booted)'; then
    echo "simulator is not booted: $simulator_id" >&2
    exit 69
fi

mkdir -p "$output_directory"

for state in "${states[@]}"; do
    xcrun simctl terminate "$simulator_id" "$bundle_id" 2>/dev/null || true
    xcrun simctl launch "$simulator_id" "$bundle_id" \
        -PiboCharacterLab \
        -PiboLabState "$state" \
        -PiboLabArtboard \
        -PiboLabClean >/dev/null

    # RootView presents Character Lab as a full-screen cover. Three seconds
    # covers that presentation plus the state's authored intro and produces a
    # stable, idle-free end-state frame.
    sleep 3

    full="$output_directory/$state-full.png"
    final="$output_directory/$state.png"
    xcrun simctl io "$simulator_id" screenshot "$full" >/dev/null

    # iPhone 17 Pro is @3x. The lab centers the authored 300pt artboard, so the
    # centered 900px crop is the exact Figma comparison surface.
    sips --cropToHeightWidth 900 900 "$full" --out "$final" >/dev/null
    sips --resampleHeightWidth 300 300 "$final" >/dev/null
    echo "captured $state"
done

