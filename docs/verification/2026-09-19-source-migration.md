# Clean source-publication migration

The owner approved retaining the old repository privately and publishing the
sanitized history through a new repository on 2026-09-19.

## Completed staging

- Renamed the old repository and archived it, preserving its PRs and historical
  records privately and read-only. Nothing was deleted.
- Created a distinct, empty, private `zjimmm/lidripple` repository (not a fork or
  repository import).
- Transferred only the sanitized `main` branch, with the intended GitHub noreply
  author/committer identity. No old branches, PR refs, tags, releases, or local
  backup refs were intentionally transferred.
- The previous PR-retention blocker in the September 16 record applies to the
  private archive, not the new repository. Old local worktrees and backups still
  contain historical references and must not be mirror-pushed to the new repo.

## Publication checklist

- Independently clone and scan the new repository, checking all advertised refs.
- Verify CI on the new repository.
- Confirm public visibility at the final publication step, then enable and verify
  GitHub private vulnerability reporting before announcing the source.
- Publishing the source is not publishing the app binary. The notarized candidate
  still needs the remaining release packaging/install checks before a GitHub Release.

This staging record does not claim public visibility or a published binary release.
