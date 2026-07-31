#!/bin/bash

set -euo pipefail

figma_directory="${1:-.tmp/animation-verification/figma-states}"
simulator_directory="${2:-.tmp/animation-verification/simulator-states}"
states=(default weak pigu muscle tired angry dive boring coolhide sleep-1 sleep-2 awake)
minimum_ssim="0.990000"
maximum_edge_delta="2"

for tool in ffmpeg ffprobe; do
    if ! command -v "$tool" >/dev/null; then
        echo "missing required tool: $tool" >&2
        exit 69
    fi
done

visible_box() {
    ffmpeg -hide_banner -i "$1" \
        -vf "colorkey=0xc0c0c0:0.01:0.0,alphaextract,bbox=min_val=10" \
        -frames:v 1 -f null - 2>&1 \
        | sed -n 's/.*crop=\([0-9]*\):\([0-9]*\):\([0-9]*\):\([0-9]*\).*/\1 \2 \3 \4/p' \
        | tail -1
}

maximum_box_edge_delta() {
    awk -v first="$1 $2 $3 $4" -v second="$5 $6 $7 $8" '
        BEGIN {
            split(first, a, " "); split(second, b, " ")
            # bbox output is width height minX minY. Compare all four edges,
            # not only origin and size, so opposite-direction errors cannot
            # cancel each other out.
            ae[1] = a[3]; ae[2] = a[4]
            ae[3] = a[3] + a[1] - 1; ae[4] = a[4] + a[2] - 1
            be[1] = b[3]; be[2] = b[4]
            be[3] = b[3] + b[1] - 1; be[4] = b[4] + b[2] - 1
            maximum = 0
            for (edge = 1; edge <= 4; edge++) {
                delta = ae[edge] - be[edge]
                if (delta < 0) delta = -delta
                if (delta > maximum) maximum = delta
            }
            print maximum
        }
    '
}

printf '%-10s %-10s %-10s\n' state ssim edge_delta

failed=0
for state in "${states[@]}"; do
    figma="$figma_directory/$state.png"
    simulator="$simulator_directory/$state.png"

    if [[ ! -f "$figma" || ! -f "$simulator" ]]; then
        echo "missing comparison image for $state" >&2
        failed=1
        continue
    fi

    for image in "$figma" "$simulator"; do
        dimensions=$(ffprobe -v error -select_streams v:0 \
            -show_entries stream=width,height -of csv=p=0:s=x "$image")
        if [[ "$dimensions" != "300x300" ]]; then
            echo "$image is $dimensions; expected 300x300" >&2
            failed=1
        fi
    done

    ssim=$(ffmpeg -hide_banner -i "$figma" -i "$simulator" \
        -lavfi ssim -f null - 2>&1 \
        | sed -n 's/.* All:\([^ ]*\).*/\1/p' \
        | tail -1)
    figma_box=$(visible_box "$figma")
    simulator_box=$(visible_box "$simulator")

    if [[ -z "$ssim" || -z "$figma_box" || -z "$simulator_box" ]]; then
        echo "could not measure $state" >&2
        failed=1
        continue
    fi

    # shellcheck disable=SC2086
    edge_delta=$(maximum_box_edge_delta $figma_box $simulator_box)
    printf '%-10s %-10s %-10s\n' "$state" "$ssim" "$edge_delta"

    if ! awk -v value="$ssim" -v minimum="$minimum_ssim" \
        'BEGIN { exit(value >= minimum ? 0 : 1) }'; then
        echo "$state SSIM $ssim is below $minimum_ssim" >&2
        failed=1
    fi
    if (( edge_delta > maximum_edge_delta )); then
        echo "$state edge delta $edge_delta exceeds ${maximum_edge_delta}px" >&2
        failed=1
    fi
done

exit "$failed"
