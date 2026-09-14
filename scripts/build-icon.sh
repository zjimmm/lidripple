#!/bin/bash
set -euo pipefail

# Package the owner-approved artwork without altering its design.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
icon_source="$repo_root/Packaging/AppIcon.png"
icon_stage="$(mktemp -d /private/tmp/lidripple-icon.XXXXXX)"
iconset="$icon_stage/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$icon_source" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$icon_source" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$repo_root/Packaging/AppIcon.icns"
echo "Built Packaging/AppIcon.icns from owner-approved artwork."
