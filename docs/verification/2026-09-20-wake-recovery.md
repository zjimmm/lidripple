# v1.0.1 wake recovery candidate

Published as v1.0.1 on 2026-09-21.

## Release verification

- Source/tag: `485c5b22986f3640ab5a2b0f5437c7eb3f58ec1c`; CI run `35514213236` passed.
- Universal app and DMG signed, accepted by Apple, stapled and validated.
- Gatekeeper, entitlements, bundle/DMG contents, mounted-copy equality, launch
  smoke and SHA-256 passed. Homebrew remains deferred under the DMG-only policy.
- Anonymous public download matched local SHA-256:
  `8278142895dc72281ec44ac9a2047e63ce85d98ef3f8ae72dd6670ae7604300b`.
- Release: https://github.com/zjimmm/lidripple/releases/tag/v1.0.1
- Existing v1.0.0 assets were not changed.

## Cause and change

The running Mac supplies an active console session but omits the private
`CGSSessionScreenIsLocked` property while unlocked. v1.0.0 treats this as unknown,
so wake/unlock leaves input and capture stopped until explicit menu interaction.

The new shared reader also reads the root `IOConsoleLocked` Boolean through
IOKit. Apple's XNU source identifies this property as an OSBoolean:
https://github.com/apple-oss-distributions/xnu/blob/main/iokit/IOKit/IOKitKeysPrivate.h

This remains an OS implementation detail, not a guaranteed public lock-state API.
Either explicit locked result wins. Unlocked evidence requires a current console
session whose audit identity is stable across the reads. Neither field present
means unknown; missing/malformed registry data never defaults to false. Runtime
authorization re-reads state rather than caching an unlocked value. Distributed
notifications remain hints, not authority. Cross-API reads are not atomic; existing
generation invalidation, lock/sleep teardown and post-capture checks remain necessary.

Unlock notification handling retries the snapshot for at most 500 ms to accommodate
propagation delay, abandoning it after an intervening restriction generation.
The menu also refreshes TCC state without presenting another permission prompt.

## Evidence and next gate

- On this machine, unlocked registry state is explicitly false, and the required
  session audit-identity field exists. No identifying values were logged.
- 314 warnings-as-errors tests passed, including all 27 combinations of optional
  console/session-lock/registry-lock state, malformed evidence, and three repeated
  sleep/unlock cycles. Existing forged/unknown notification tests remain passing.
- Owner confirmed the installed signed candidate works after the requested full
  close/sleep, reopen/unlock, and subsequent close sequence without a menu click.
- Separate fast-user-switching and locked-screen physical testing was not reported;
  no new claim of hardware qualification is made. Negative-state automated tests pass.
- v1.0.0 release assets remain unchanged.
