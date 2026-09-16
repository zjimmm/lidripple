# Pre-publication security cleanup

Owner approved remediation and noreply history rewriting on 2026-09-16.
Repository remains private; no GitHub release has been published.

## Implemented

- Background distributed unlock events require both an active event snapshot and
  a current positively active console session. Unknown lock state fails closed.
- A direct status-menu interaction remains the fallback when macOS omits its lock
  state. In that case users may need to open the menu after unlocking; automatic
  opening animation can be skipped. No claim of an authenticated notification
  sender is made.
- Tests cover unknown/forged active payload rejection, direct menu recovery,
  intervening lock/sleep, and capture concurrency. All 310 local tests passed.
- Added credential/export exclusions and a version- and checksum-pinned Gitleaks
  CI job scanning fetched history with redacted output and read-only permissions.
- Privacy copy distinguishes transient captured pixels from preferences and
  pixel-free diagnostic logs. No secure-memory-erasure guarantee is made.
- Rewrote both remote branch histories to the owner's verified GitHub noreply
  identity. Verified unchanged file trees and a clean post-rewrite secrets scan.
  Future commits use repository-local noreply configuration.
- Created an ignored local Git bundle before rewriting. The old dirty overlay
  worktree and other legacy local branches were deliberately preserved. Do not
  push those legacy refs; re-clone/rebase carefully when resuming older work.

## Remaining publication tasks and limits

- GitHub private vulnerability reporting could not be enabled while private
  (API returned 404). Enable and verify the direct advisory-reporting URL during
  public-source publication, before announcing a release.
- A history rewrite changes reachable branch history, not copies held by others,
  GitHub caches/unreachable objects, old CI records, local reflogs, or the private
  backup. Do not claim that personal metadata has been erased from every copy.
- Older verification records contain pre-rewrite commit IDs and historical test
  counts. They remain historical evidence, not the new release source identity.
- Rebuild/notarize the security-updated app. The previous candidate was accepted by
  Apple, but the signing script's positional JSON parsing confused the completion
  message with the status in compact JSON. Named-key parsing now replaces it.
- Notarization and automated testing do not replace an independent penetration
  test. Actual adversarial OS-event injection was not performed on the owner's
  live session. Release remains gated on artifact verification.
