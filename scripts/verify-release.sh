#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage: scripts/verify-release.sh --app APP --dmg DMG [--cask CASK] [--skip-launch-smoke]

Omit --cask only for the first verification pass before the exact DMG checksum
has been written into Casks/lidripple.rb. Final release verification requires it.
EOF
}

app=""
dmg=""
cask=""
launch_smoke=1
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app|--dmg|--cask)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; usage; exit 64; }
            case "$1" in
                --app) app="$2" ;;
                --dmg) dmg="$2" ;;
                --cask) cask="$2" ;;
            esac
            shift 2
            ;;
        --skip-launch-smoke) launch_smoke=0; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 64 ;;
    esac
done
[[ -d "$app" && "$app" == *.app && -f "$dmg" ]] || { usage; exit 64; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
dmg="$(cd "$(dirname "$dmg")" && pwd)/$(basename "$dmg")"
info="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/lidripple"

[[ "$(basename "$dmg")" == "lidripple-$version.dmg" ]] || {
    echo "DMG name must be lidripple-$version.dmg" >&2
    exit 1
}
[[ -f "$dmg.sha256" ]] || { echo "Missing checksum sidecar: $dmg.sha256" >&2; exit 1; }
expected_sidecar_hash="$(awk 'NR == 1 { print $1 }' "$dmg.sha256")"
actual_dmg_hash="$(shasum -a 256 "$dmg" | awk '{ print $1 }')"
[[ "$expected_sidecar_hash" =~ ^[0-9a-f]{64}$ && "$expected_sidecar_hash" == "$actual_dmg_hash" ]] || {
    echo "DMG checksum sidecar does not match the artifact" >&2
    exit 1
}

plutil -lint "$info"
[[ "$(plutil -extract CFBundleIdentifier raw "$info")" == "com.lidripple.app" ]]
[[ "$(plutil -extract CFBundleDisplayName raw "$info")" == "lidripple" ]]
[[ "$(plutil -extract CFBundleName raw "$info")" == "lidripple" ]]
[[ "$(plutil -extract CFBundleExecutable raw "$info")" == "lidripple" ]]
[[ "$(plutil -extract CFBundlePackageType raw "$info")" == "APPL" ]]
[[ "$(plutil -extract CFBundleIconFile raw "$info")" == "AppIcon" ]]
[[ "$(plutil -extract CFBundleShortVersionString raw "$info")" == "$version" ]]
bundle_build="$(plutil -extract CFBundleVersion raw "$info")"
[[ "$bundle_build" =~ ^[0-9]+([.][0-9]+)*$ ]] || {
    echo "CFBundleVersion must contain only dot-separated integers" >&2
    exit 1
}
[[ "$(plutil -extract LSMinimumSystemVersion raw "$info")" == "14.0" ]]
[[ "$(plutil -extract LSUIElement raw "$info")" == "true" ]]
[[ "$(plutil -extract NSHighResolutionCapable raw "$info")" == "true" ]]
[[ "$(<"$app/Contents/PkgInfo")" == "APPL????" ]]
[[ -f "$app/Contents/Resources/AppIcon.icns" ]] || {
    echo "Bundle is missing AppIcon.icns" >&2
    exit 1
}

architectures="$(lipo -archs "$executable")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
    echo "Expected arm64 and x86_64; found: $architectures" >&2
    exit 1
}
[[ "$(tr ' ' '\n' <<< "$architectures" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')" == "arm64 x86_64" ]] || {
    echo "Release executable has unexpected architecture slices: $architectures" >&2
    exit 1
}

codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --verbose=2 "$dmg"
entitlements="$(mktemp "${TMPDIR:-/tmp}/lidripple-entitlements.XXXXXX")"
mount_point="$(mktemp -d "${TMPDIR:-/tmp}/lidripple-mount.XXXXXX")"
install_root="$(mktemp -d "${TMPDIR:-/tmp}/lidripple-install.XXXXXX")"
cleanup() {
    hdiutil detach "$mount_point" -quiet >/dev/null 2>&1 || true
    rm -f "$entitlements"
    rm -rf "$mount_point" "$install_root"
}
trap cleanup EXIT
signature_info="$(codesign -dvvv "$app" 2>&1)"
[[ "$signature_info" == *"Authority=Developer ID Application:"* ]] || {
    echo "App is not signed with Developer ID Application" >&2
    exit 1
}
[[ "$signature_info" == *"runtime"* ]] || {
    echo "App signature does not enable the hardened runtime" >&2
    exit 1
}
codesign -d --entitlements - --xml "$app" > "$entitlements"
plutil -lint "$entitlements"
[[ "$(plutil -convert json -o - "$entitlements")" == "{}" ]] || {
    echo "Release app has unexpected entitlements" >&2
    exit 1
}

bundle_files="$(find "$app" \( -type f -o -type l \) -print | sed "s|$app/||" | LC_ALL=C sort)"
expected_bundle_files=$'Contents/Info.plist\nContents/MacOS/lidripple\nContents/PkgInfo\nContents/Resources/AppIcon.icns\nContents/_CodeSignature/CodeResources'
[[ "$bundle_files" == "$expected_bundle_files" ]] || {
    echo "App contains files outside the documented bundle set:" >&2
    echo "$bundle_files" >&2
    exit 1
}

spctl --assess --type execute --verbose=2 "$app"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg"
xcrun stapler validate "$app"
hdiutil verify "$dmg"
xcrun stapler validate "$dmg"

hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_point" -quiet
entries="$(find "$mount_point" -mindepth 1 -maxdepth 1 -print | sed "s|$mount_point/||" | LC_ALL=C sort)"
[[ "$entries" == $'Applications\nlidripple.app' ]] || {
    echo "DMG contains unexpected top-level files:" >&2
    echo "$entries" >&2
    exit 1
}
ditto "$mount_point/lidripple.app" "$install_root/lidripple.app"
codesign --verify --deep --strict "$install_root/lidripple.app"
cmp -s "$executable" "$install_root/lidripple.app/Contents/MacOS/lidripple" || {
    echo "Mounted DMG executable differs from the verified app" >&2
    exit 1
}
cmp -s "$info" "$install_root/lidripple.app/Contents/Info.plist" || {
    echo "Mounted DMG Info.plist differs from the verified app" >&2
    exit 1
}

if [[ "$launch_smoke" -eq 1 ]]; then
    "$install_root/lidripple.app/Contents/MacOS/lidripple" >/dev/null 2>&1 &
    smoke_pid=$!
    sleep 2
    kill "$smoke_pid" >/dev/null 2>&1 || {
        echo "Installed app exited before the launch smoke completed" >&2
        wait "$smoke_pid" || true
        exit 1
    }
    wait "$smoke_pid" || true
fi

if [[ -n "$cask" ]]; then
    [[ -f "$cask" ]] || { echo "Missing cask: $cask" >&2; exit 1; }
    expected="$(sed -nE 's/^[[:space:]]*sha256[[:space:]]+"([0-9a-f]{64})".*/\1/p' "$cask")"
    [[ "$expected" =~ ^[0-9a-f]{64}$ ]] || { echo "Cask has no exact SHA-256" >&2; exit 1; }
    actual="$(shasum -a 256 "$dmg" | awk '{print $1}')"
    [[ "$actual" == "$expected" ]] || { echo "Cask checksum does not match DMG" >&2; exit 1; }
    grep -Eq '^[[:space:]]*version "'"$version"'"$' "$cask" || {
        echo "Cask version does not match VERSION" >&2
        exit 1
    }
    expected_literal_url="https://github.com/zjimmm/lidripple/releases/download/v$version/lidripple-$version.dmg"
    expected_interpolated_url='https://github.com/zjimmm/lidripple/releases/download/v#{version}/lidripple-#{version}.dmg'
    grep -Fq "$expected_literal_url" "$cask" || grep -Fq "$expected_interpolated_url" "$cask" || {
        echo "Cask URL does not match the immutable versioned artifact" >&2
        exit 1
    }
else
    echo "NOTICE: cask checksum gate skipped; this is not a final release verification"
fi

echo "Release verification passed for lidripple $version ($architectures)"
