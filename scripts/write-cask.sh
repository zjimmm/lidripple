#!/bin/bash
set -euo pipefail

usage() {
    echo "Usage: scripts/write-cask.sh --dmg DMG --output CASK.rb" >&2
}

dmg=""
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dmg|--output)
            [[ $# -ge 2 ]] || { usage; exit 64; }
            if [[ "$1" == --dmg ]]; then dmg="$2"; else output="$2"; fi
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) usage; exit 64 ;;
    esac
done
[[ -f "$dmg" && -n "$output" ]] || { usage; exit 64; }
[[ ! -e "$output" && ! -L "$output" ]] || {
    echo "Refusing to overwrite $output" >&2
    exit 1
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "VERSION is not a semantic version" >&2
    exit 1
}
[[ "$(basename "$dmg")" == "lidripple-$version.dmg" ]] || {
    echo "DMG filename does not match VERSION" >&2
    exit 1
}
[[ -f "$dmg.sha256" ]] || { echo "Missing $dmg.sha256" >&2; exit 1; }
expected="$(awk 'NR == 1 { print $1 }' "$dmg.sha256")"
sidecar_name="$(awk 'NR == 1 { print $2 }' "$dmg.sha256")"
sidecar_fields="$(awk 'NR == 1 { print NF }' "$dmg.sha256")"
sidecar_lines="$(awk 'END { print NR }' "$dmg.sha256")"
actual="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
[[ "$sidecar_lines" == 1 && "$sidecar_fields" == 2 &&
   "$sidecar_name" == "$(basename "$dmg")" &&
   "$expected" =~ ^[0-9a-f]{64}$ && "$expected" == "$actual" ]] || {
    echo "DMG checksum does not match its sidecar" >&2
    exit 1
}

output_dir="$(dirname "$output")"
[[ -d "$output_dir" ]] || { echo "Output directory does not exist" >&2; exit 1; }
staged="$(mktemp "$output_dir/.lidripple-cask.XXXXXX")"
cleanup() { [[ ! -e "$staged" ]] || rm "$staged"; }
trap cleanup EXIT

cat > "$staged" <<EOF
cask "lidripple" do
  version "$version"
  sha256 "$actual"

  url "https://github.com/zjimmm/lidripple/releases/download/v#{version}/lidripple-#{version}.dmg"
  name "LidRipple"
  desc "Menu bar fold animation for the built-in MacBook display"
  homepage "https://github.com/zjimmm/lidripple"

  depends_on macos: :sonoma

  app "LidRipple.app"

  uninstall quit:       "com.lidripple.app",
            login_item: "LidRipple"

  zap trash: "~/Library/Preferences/com.lidripple.app.plist"
end
EOF

ruby -c "$staged" >/dev/null
mv "$staged" "$output"
echo "Wrote $output (lidripple $version; SHA-256 $actual)"
