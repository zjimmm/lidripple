# Releasing LidRipple

This is a maintainer procedure. A CI build or ad-hoc signature is not a release. The
published DMG must be a universal, hardened-runtime, Developer ID–signed artifact that
Apple accepted and that carries a stapled notarization ticket.

## Credentials and local prerequisites

- A current Apple Developer Program membership
- A `Developer ID Application` certificate and private key in the login keychain
- Xcode command-line tools with `notarytool`
- Either a named `notarytool` keychain profile or an App Store Connect API key, key ID,
  and issuer ID
- Homebrew for final cask style, audit, install, and uninstall checks
- GitHub owner authorization for every push, tag, or Release mutation

Prefer a keychain profile created interactively:

```sh
xcrun notarytool store-credentials lidripple-notary \
  --apple-id YOUR_APPLE_ID \
  --team-id YOUR_TEAM_ID
```

Enter the app-specific password only at the secure interactive prompt.
Never paste secrets into a shell script, commit them, add them to a command transcript,
or run the release scripts under shell tracing (`set -x`). Redact Apple IDs, team IDs,
key IDs, issuer IDs, certificate serials, and notarization submission IDs from public
verification records.

## Immutable version invariants

For v1.0.0, all of these must describe the same object:

- `VERSION` contains `1.0.0`.
- The app has `CFBundleShortVersionString=1.0.0`.
- The tag is `v1.0.0` on the exact reviewed commit.
- The release asset is named `lidripple-1.0.0.dmg`.
- `Casks/lidripple.rb` has `version "1.0.0"`, the v1.0.0 GitHub Release URL, and the
  exact SHA-256 of that final stapled DMG.

Never rebuild between computing the final checksum, committing the cask, tagging, and
uploading the asset. A different byte sequence is a different release candidate.

## Release sequence

**v1 DMG-only exception (owner approved 2026-09-19):** Homebrew distribution and
cask audit/install/reinstall/uninstall/zap gates are deferred. Do not publish a
cask or advertise Homebrew support. App/DMG signature, notarization, integrity,
launch and post-upload checksum gates remain mandatory. The existing candidate
passed exact cask checksum validation locally before that temporary cask was
removed; the artifact itself is unchanged. Future Homebrew releases must complete
the full procedure below.

1. S6's reference comparison was explicitly deferred for v1 by the owner on
   2026-09-15; use owner visual acceptance without reference-parity claims or
   redistribution of private footage. Confirm every applicable v1 M5
   row in `docs/verification/2026-09-12-m5-release-matrix.md`. S7 for v1 is an
   **automated safe-degradation gate**: no-HID selection and bounded recovery,
   resource/timer cleanup, immediate sleep seal, fresh post-unlock frame subject to
   session/display/Screen Recording conditions, permission handling, and accurate
   mode copy. Leave its checkboxes unchecked until the reviewed candidate passes.
   A visible sensor-less close and physical qualification on a genuinely no-HID Mac
   are separately tracked post-v1, not v1 pass criteria. Fresh-profile TCC,
   sensor-equipped behavior, installed login item, and privacy checks still require
   physical evidence.
   Before release, verify that the app, README, supported-model table, and release
   notes call the no-HID path **experimental/unverified** and say that close animation
   is currently unavailable. The approximately 550 ms program is unit-tested but has
   no production early trigger; do not present it as a working close animation.
   Angle tracking and physical mid-close reversal are unavailable in that mode, and a
   no-sleep clamshell close may be undetectable. Only consider a future visible close
   best-effort after a supported early trigger is measured while the built-in panel
   can still display frames. Do not delay forced sleep or draw over `loginwindow`.
2. Confirm the public copyright name. Sponsorship is optional, not a release gate.
3. From a clean, synchronized `main`, run the automated gates:

   ```sh
   test "$(git branch --show-current)" = main
   test -z "$(git status --porcelain --untracked-files=all)"
   swift test -Xswiftc -warnings-as-errors
   swift build -c release -Xswiftc -warnings-as-errors
   scripts/build-app.sh --release --output dist
   ```

   `build-app.sh --release` queries the current `origin/main` and refuses to
   assemble a release bundle if `HEAD` differs or the remote cannot be reached.

4. Sign and notarize. Use the exact identity printed by `security find-identity -v -p
   codesigning`:

   ```sh
   scripts/sign-and-notarize.sh \
     --app dist/LidRipple.app \
     --identity "Developer ID Application: YOUR NAME (TEAMID)" \
     --keychain-profile lidripple-notary \
     --output dist/lidripple-1.0.0.dmg
   ```

   API-key authentication is also supported with `--api-key`, `--key-id`, and
   `--issuer`. Do not record those values in the release matrix.

5. Run the first artifact verification before a cask exists:

   ```sh
   scripts/verify-release.sh \
     --app dist/LidRipple.app \
     --dmg dist/lidripple-1.0.0.dmg
   ```

   This also checks the adjacent `.dmg.sha256` sidecar. Keep the DMG and sidecar in the
   same directory and do not rename either one.

6. Generate `Casks/lidripple.rb` from the verified DMG and matching checksum sidecar:

   ```sh
   mkdir -p Casks
   scripts/write-cask.sh --dmg dist/lidripple-1.0.0.dmg --output Casks/lidripple.rb
   ```

   The generator refuses to overwrite an existing cask or use a mismatched digest.
   Inspect the generated file; it must contain the exact 64-character SHA-256—never
   `:no_check`—and this immutable URL:

   ```text
   https://github.com/zjimmm/lidripple/releases/download/v1.0.0/lidripple-1.0.0.dmg
   ```

   The cask must require Sonoma or later, install `LidRipple.app`, and limit zap cleanup
   to `com.lidripple.app` preferences and lidripple's own login-item state.

7. Verify the cask metadata against the same local artifact:

   ```sh
   scripts/verify-release.sh \
     --app dist/LidRipple.app \
     --dmg dist/lidripple-1.0.0.dmg \
     --cask Casks/lidripple.rb
   brew style Casks/lidripple.rb
   brew audit --cask --strict Casks/lidripple.rb
   ```

   The cask's GitHub Release URL does not exist yet. Do not claim an install pass at
   this stage; verify the signed DMG's mount/copy/launch path with
   `verify-release.sh` and inspect the cask's zap targets manually.

8. Record redacted commands and results in the release matrix. Commit the cask and
   matrix. Review the resulting commit and rerun checksum verification.
9. With explicit owner approval, push the reviewed commit and create/push tag `v1.0.0`.
10. With separate explicit owner approval, create the GitHub Release and upload the
    already-verified DMG and `.sha256` file. Do not rebuild. Download the published asset
    once and confirm its SHA-256 matches the cask.
11. Only after the immutable asset exists at the cask URL, perform the actual cask
    installation, reinstall/upgrade, uninstall, zap, and clean-account Gatekeeper checks:

    ```sh
    brew install --cask ./Casks/lidripple.rb
    open -a lidripple
    brew reinstall --cask ./Casks/lidripple.rb
    brew uninstall --cask lidripple
    brew install --cask ./Casks/lidripple.rb
    brew uninstall --zap --cask lidripple
    ```

    Confirm Service Management no longer reports lidripple's modern
    `SMAppService.mainApp` registration after uninstall, and that upgrade/reinstall
    preserves a user-enabled Launch at Login setting. Homebrew's `login_item:`
    stanza targets legacy System Events login items; do not treat its presence as
    proof of modern registration cleanup. Confirm zap removes only lidripple state.
    If any gate fails, withdraw the release rather than replacing bytes under the
    published versioned URL.

## Troubleshooting and rollback

- If notarization fails, inspect the `notarytool` log locally. Fix the cause, increment
  the release candidate, rebuild from clean `main`, and restart the entire checksum
  sequence. Never edit or re-sign an artifact whose digest is already in the cask.
- If `spctl` rejects the app, check certificate validity, hardened-runtime flags,
  nested-code signing order, and staple status. An accepted submission alone is not a
  passing Gatekeeper result.
- If the cask audit or install fails, do not publish. Correct the cask against the same
  immutable artifact when possible; rebuild only when the artifact itself is defective.
- If a bad release was published, mark it withdrawn, remove the cask version, and issue
  a new patch version. Do not replace assets beneath an existing tag or URL.
- If credentials or identifiers leak into logs, revoke/rotate them before continuing and
  remove the sensitive material from public history using the repository owner's
  incident process.
- If `notarytool` finishes with any status other than `Accepted`, stop. Do not staple,
  checksum, add a cask, tag, or upload that candidate.
