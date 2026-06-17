---
description: Pull upstream/main into the fork — FF main, rebase feat/* branches, rebuild release/collide
---

Run `bash scripts/sync-upstream.sh` from the repo root and surface the result.

The script is deterministic — it does all the git work and prints a SUMMARY block at the end. Your job is to read its output and:

1. **Exit 0 (clean):** Confirm it's done. Report the new main SHA and which branches were rebased.
2. **Exit 1 (preconditions):** Tell the user what's blocking — usually uncommitted changes. Don't try to fix it; ask.
3. **Exit 2 (main diverged):** Stop. Tell the user that commits landed directly on origin/main and need investigation. Do not try to force-push or "fix" main.
4. **Exit 3 (conflicts):** Read the SUMMARY to see which branches failed. For each failed branch:
   - Check out the branch locally.
   - Run `git rebase main` (or `git merge` for release/collide).
   - Resolve conflicts. For `feat/no-telemetrydeck`, conflicts almost always come from upstream adding new `TelemetryDeck.signal(...)` calls — delete the upstream additions (keep "ours" side).
   - Force-push with `--force-with-lease`.
   - After all conflicts resolved, re-run `bash scripts/sync-upstream.sh` to rebuild release/collide.

Be terse. The user knows the layout. Just tell them what happened and what's next.
