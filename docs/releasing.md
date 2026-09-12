# Releasing lidripple

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
  --team-id YOUR_TEAM_ID \
  --password YOUR_APP_SPECIFIC_PASSWORD
```

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

1. Confirm M4's comparison GIF/provenance/human approval and every applicable M5 row in
   `docs/verification/2026-09-12-m5-release-matrix.md`. S7, fresh-profile TCC, installed
   login item, and privacy checks require physical evidence.
2. Confirm the public copyright name and active GitHub Sponsors profile.
3. From a clean, synchronized `main`, run the automated gates:

   ```sh
   test "$(git branch --show-current)" = main
   test -z "$(git status --porcelain --untracked-files=all)"
   swift test -Xswiftc -warnings-as-errors
   swift build -c release -Xswiftc -warnings-as-errors
   scripts/build-app.sh --release --output dist
   ```

4. Sign and notarize. Use the exact identity printed by `security find-identity -v -p
   codesigning`:

   ```sh
   scripts/sign-and-notarize.sh \
     --app dist/lidripple.app \
     --identity "Developer ID Application: YOUR NAME (TEAMID)" \
     --keychain-profile lidripple-notary \
     --output dist/lidripple-1.0.0.dmg
   ```

   API-key authentication is also supported with `--api-key`, `--key-id`, and
   `--issuer`. Do not record those values in the release matrix.

5. Run the first artifact verification before a cask exists:

   ```sh
   scripts/verify-release.sh \
     --app dist/lidripple.app \
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

   The cask must require Sonoma or later, install `lidripple.app`, and limit zap cleanup
   to `com.lidripple.app` preferences and lidripple's own login-item state.

7. Verify the cask metadata against the same local artifact:

   ```sh
   scripts/verify-release.sh \
     --app dist/lidripple.app \
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

    Confirm zap removes only lidripple state. If any gate fails, withdraw the release
    rather than replacing bytes under the published versioned URL.

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
