# DMG publication checkpoint

LidRipple 1.0.0 was published on 2026-09-19 as a DMG-only release.
Source is public; the original repository remains privately archived.

## Publication result

- Tag `v1.0.0`: `f7402616ecfcf4a170698df476c7b1870ba8e920`.
- CI run `35409062483` passed, including secret scanning, warnings-as-errors tests,
  release build, and universal app/DMG packaging.
- Release: https://github.com/zjimmm/lidripple/releases/tag/v1.0.0
- Anonymous download of the published DMG and sidecar passed SHA-256 verification.
- GitHub private vulnerability reporting is enabled.
- No artifact rebuild, re-sign, or replacement occurred during publication.

## Verified

- Existing immutable version 1.0.0 candidate, app source `2f01bd3`.
- Later source changes through `3a1e031` affect only verification scripts/docs,
  not the shipped app.
- App and DMG signatures, hardened runtime, empty entitlements, arm64/x86_64
  slices, notarization staples and Gatekeeper acceptance passed.
- DMG integrity, allowed contents, mounted app equality, temporary-copy launch
  smoke and exact cask checksum validation passed with `scripts/verify-release.sh`.
- SHA-256: `470bb74ffa979a77fea0d131c1fc41736fc0d241f323323cbd3c1fb6abb1c7c4`.
- Generated the cask from the existing DMG; no rebuild or re-sign occurred.
- Corrected cask hash alignment in the generator and generated file.

## Blocked / not claimed

- Homebrew strict audit stopped because the installed Xcode 26.2 does not meet
  Homebrew's current Xcode 27.0 requirement. This is not an artifact rejection.
- Homebrew installation, reinstall, uninstall and zap checks have not passed.
- Owner approved DMG-only v1 and deferral of Homebrew distribution/checks.
  The temporary generated cask was removed; no Homebrew support is advertised.
- Existing owner waiver covers repeat physical lid testing; it is not represented
  as fresh-profile permission, login-item or Homebrew acceptance evidence.
- Physical tests were not repeated. Homebrew and fresh-profile acceptance are
  not claimed by this publication record.
