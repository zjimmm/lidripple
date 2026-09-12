#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage:
  scripts/sign-and-notarize.sh --app APP --identity "Developer ID Application: ..." \
    (--keychain-profile PROFILE | --api-key PATH --key-id ID --issuer UUID) \
    [--output DMG]

Credentials are passed directly to notarytool and are never written or echoed.
EOF
}

app=""
identity=""
profile=""
api_key=""
key_id=""
issuer=""
output=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --app|--identity|--keychain-profile|--api-key|--key-id|--issuer|--output)
            [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; usage; exit 64; }
            case "$1" in
                --app) app="$2" ;;
                --identity) identity="$2" ;;
                --keychain-profile) profile="$2" ;;
                --api-key) api_key="$2" ;;
                --key-id) key_id="$2" ;;
                --issuer) issuer="$2" ;;
                --output) output="$2" ;;
            esac
            shift 2
            ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage; exit 64 ;;
    esac
done

[[ -n "$app" && -d "$app" && "$app" == *.app ]] || { usage; exit 64; }
[[ "$identity" == "Developer ID Application:"* ]] || {
    echo "--identity must be an explicit Developer ID Application identity" >&2
    exit 1
}

if [[ -n "$profile" ]]; then
    [[ -z "$api_key" && -z "$key_id" && -z "$issuer" ]] || {
        echo "Choose a keychain profile or API-key credentials, not both" >&2
        exit 1
    }
    notary_args=(--keychain-profile "$profile")
else
    [[ -f "$api_key" && -n "$key_id" && -n "$issuer" ]] || {
        echo "API authentication requires --api-key, --key-id, and --issuer" >&2
        exit 1
    }
    notary_args=(--key "$api_key" --key-id "$key_id" --issuer "$issuer")
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$(cd "$(dirname "$app")" && pwd)/$(basename "$app")"
version="$(tr -d '[:space:]' < "$repo_root/VERSION")"
output="${output:-$repo_root/dist/lidripple-$version.dmg}"
[[ "$output" = /* ]] || output="$PWD/$output"
mkdir -p "$(dirname "$output")"
output="$(cd "$(dirname "$output")" && pwd)/$(basename "$output")"

[[ "$(plutil -extract CFBundleShortVersionString raw "$app/Contents/Info.plist")" == "$version" ]] || {
    echo "App version does not match VERSION" >&2
    exit 1
}
[[ ! -e "$output" && ! -e "$output.sha256" ]] || {
    echo "Refusing to overwrite an existing release artifact: $output" >&2
    exit 1
}

architectures="$(lipo -archs "$app/Contents/MacOS/lidripple")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
    echo "Release app must contain arm64 and x86_64 slices; found: $architectures" >&2
    exit 1
}

codesign --force --options runtime --timestamp --sign "$identity" \
    "$app/Contents/MacOS/lidripple"
codesign --force --options runtime --timestamp --sign "$identity" \
    --entitlements "$repo_root/Packaging/lidripple.entitlements" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

notary_stage="$(mktemp -d "${TMPDIR:-/tmp}/lidripple-notary.XXXXXX")"
cleanup() { rm -rf "$notary_stage"; }
trap cleanup EXIT

submit_and_require_accepted() {
    local artifact="$1"
    local result="$notary_stage/$(basename "$artifact").notary.json"
    local status

    xcrun notarytool submit "$artifact" "${notary_args[@]}" --wait --output-format json > "$result"
    status="$(awk -F'"' '/"status"[[:space:]]*:/ { print $4; exit }' "$result")"
    [[ "$status" == "Accepted" ]] || {
        echo "Notarization did not reach Accepted status for $(basename "$artifact"): ${status:-unknown}" >&2
        exit 1
    }
}

ditto -c -k --keepParent "$app" "$notary_stage/lidripple.app.zip"
submit_and_require_accepted "$notary_stage/lidripple.app.zip"
xcrun stapler staple "$app"
xcrun stapler validate "$app"

"$repo_root/scripts/make-dmg.sh" "$app" "$output"
codesign --force --timestamp --sign "$identity" "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")") > "$output.sha256"

submit_and_require_accepted "$output"
xcrun stapler staple "$output"
xcrun stapler validate "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")") > "$output.sha256"

echo "Signed, notarized, and stapled: $output"
echo "Final checksum: $output.sha256"
