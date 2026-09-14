#!/bin/bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/build-app.sh [--release] [--adhoc-sign | --sign-identity ID] [--output DIR]

Builds arm64 and x86_64 release executables, combines them into a universal
LidRipple.app, and optionally signs it. --sign-identity accepts a local code-signing
identity for development builds; unlike --adhoc-sign, it keeps a stable macOS
Screen Recording permission identity across rebuilds. --release requires a clean
main checkout. Developer ID signing is performed by sign-and-notarize.sh.
EOF
}

release_build=0
adhoc_sign=0
sign_identity=""
output_dir=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --release) release_build=1; shift ;;
        --adhoc-sign) adhoc_sign=1; shift ;;
        --sign-identity)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            [[ -n "$2" ]] || { usage >&2; exit 64; }
            sign_identity="$2"; shift 2 ;;
        --output)
            [[ $# -ge 2 ]] || { usage >&2; exit 64; }
            output_dir="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 64 ;;
    esac
done

[[ "$adhoc_sign" -eq 0 || -z "$sign_identity" ]] || {
    echo "Choose either --adhoc-sign or --sign-identity, not both" >&2
    exit 64
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(tr -d '[:space:]' < VERSION)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    echo "VERSION must contain one semantic version such as 1.0.0" >&2
    exit 1
}
build_version="${LIDRIPPLE_BUILD_NUMBER:-${version}}"
[[ "$build_version" =~ ^[0-9]+([.][0-9]+)*$ ]] || {
    echo "LIDRIPPLE_BUILD_NUMBER must contain only dot-separated integers" >&2
    exit 1
}

plutil -lint Packaging/Info.plist Packaging/lidripple.entitlements
[[ "$(plutil -extract CFBundleShortVersionString raw Packaging/Info.plist)" == "__LIDRIPPLE_VERSION__" ]] || {
    echo "Packaging/Info.plist must retain the __LIDRIPPLE_VERSION__ token" >&2
    exit 1
}
[[ "$(plutil -extract CFBundleVersion raw Packaging/Info.plist)" == "__LIDRIPPLE_BUILD__" ]] || {
    echo "Packaging/Info.plist must retain the __LIDRIPPLE_BUILD__ token" >&2
    exit 1
}
[[ "$(plutil -convert json -o - Packaging/lidripple.entitlements)" == "{}" ]] || {
    echo "Packaging/lidripple.entitlements must remain empty" >&2
    exit 1
}

if [[ "$release_build" -eq 1 ]]; then
    [[ "$(git branch --show-current)" == "main" ]] || {
        echo "Release bundles must be built from main" >&2
        exit 1
    }
    [[ -z "$(git status --porcelain --untracked-files=all)" ]] || {
        echo "Release bundles require a clean checkout" >&2
        exit 1
    }
    if ! remote_main="$(GIT_TERMINAL_PROMPT=0 git ls-remote --exit-code origin refs/heads/main | awk 'NR == 1 { print $1 }')"; then
        echo "Cannot verify the current origin/main; release builds require a reachable remote" >&2
        exit 1
    fi
    [[ -n "$remote_main" && "$(git rev-parse HEAD)" == "$remote_main" ]] || {
        echo "Release bundles require main to match the current origin/main" >&2
        exit 1
    }
fi

output_dir="${output_dir:-$repo_root/dist}"
app="$output_dir/LidRipple.app"
[[ ! -e "$app" && ! -L "$app" ]] || {
    echo "Refusing to overwrite existing bundle: $app" >&2
    exit 1
}
[[ -f Packaging/AppIcon.icns ]] || {
    echo "Packaging/AppIcon.icns is required before assembling an app bundle" >&2
    exit 1
}

mkdir -p "$output_dir"
bundle_stage="$(mktemp -d "$output_dir/.lidripple-app.XXXXXX")"
cleanup() { rm -rf "$bundle_stage"; }
trap cleanup EXIT
staged_app="$bundle_stage/LidRipple.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"

for arch in arm64 x86_64; do
    swift build -c release --arch "$arch" -Xswiftc -warnings-as-errors --product LidRippleApp
    bin_path="$(swift build -c release --arch "$arch" --show-bin-path)/LidRippleApp"
    [[ -x "$bin_path" ]] || { echo "Missing $arch executable: $bin_path" >&2; exit 1; }
    cp "$bin_path" "$bundle_stage/lidripple-$arch"
done

lipo -create \
    "$bundle_stage/lidripple-arm64" \
    "$bundle_stage/lidripple-x86_64" \
    -output "$staged_app/Contents/MacOS/lidripple"
rm "$bundle_stage/lidripple-arm64" "$bundle_stage/lidripple-x86_64"

cp Packaging/Info.plist "$staged_app/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$version" "$staged_app/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$build_version" "$staged_app/Contents/Info.plist"
cp Packaging/AppIcon.icns "$staged_app/Contents/Resources/AppIcon.icns"
printf 'APPL????' > "$staged_app/Contents/PkgInfo"
chmod 755 "$staged_app/Contents/MacOS/lidripple"

plutil -lint "$staged_app/Contents/Info.plist"
[[ "$(plutil -extract CFBundleShortVersionString raw "$staged_app/Contents/Info.plist")" == "$version" ]]
[[ "$(plutil -extract CFBundleExecutable raw "$staged_app/Contents/Info.plist")" == "lidripple" ]]
[[ "$(plutil -extract LSMinimumSystemVersion raw "$staged_app/Contents/Info.plist")" == "14.0" ]]
[[ "$(plutil -extract LSUIElement raw "$staged_app/Contents/Info.plist")" == "true" ]]
architectures="$(lipo -archs "$staged_app/Contents/MacOS/lidripple")"
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]] || {
    echo "Universal executable is missing an architecture: $architectures" >&2
    exit 1
}

if [[ "$adhoc_sign" -eq 1 || -n "$sign_identity" ]]; then
    signature="-"
    if [[ -n "$sign_identity" ]]; then signature="$sign_identity"; fi
    codesign --force --options runtime --sign "$signature" \
        --entitlements Packaging/lidripple.entitlements "$staged_app"
    codesign --verify --deep --strict --verbose=2 "$staged_app"
fi

mv "$staged_app" "$app"
echo "Built $app ($version; $architectures)"
