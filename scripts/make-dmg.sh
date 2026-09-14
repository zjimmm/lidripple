#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: scripts/make-dmg.sh APP_PATH [OUTPUT_DMG]" >&2
}

[[ $# -ge 1 && $# -le 2 ]] || { usage; exit 64; }
app="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[[ -d "$app" && "$app" == *.app ]] || { echo "Not an app bundle: $app" >&2; exit 1; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
output="${2:-$repo_root/dist/lidripple-$version.dmg}"
[[ "$output" = /* ]] || output="$PWD/$output"
[[ ! -e "$output" && ! -L "$output" &&
   ! -e "$output.sha256" && ! -L "$output.sha256" ]] || {
    echo "Refusing to overwrite an existing DMG or checksum: $output" >&2
    exit 1
}
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"

stage="$(mktemp -d "${TMPDIR:-/tmp}/lidripple-dmg.XXXXXX")"
cleanup() { rm -rf "$stage"; }
trap cleanup EXIT

ditto "$app" "$stage/LidRipple.app"
ln -s /Applications "$stage/Applications"
hdiutil create \
    -volname "LidRipple" \
    -srcfolder "$stage" \
    -format UDZO \
    "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")") > "$output.sha256"
echo "Created $output"
echo "Checksum: $output.sha256"
