#!/usr/bin/env bash
# sync-upstream.sh — pull upstream changes into the heysamtexas/muesli fork
#
# Fast-forwards main to upstream/main, rebases each feat/* branch onto the new
# main, then rebuilds release/collide = main + (each feat/* branch merged).
#
# Idempotent. Exit codes:
#   0 — clean (either no upstream changes, or everything synced cleanly)
#   1 — preconditions failed (uncommitted changes, missing remotes, etc.)
#   2 — main has diverged from upstream — refuses to force-push main
#   3 — one or more feat/* branches or release/collide hit conflicts
#       (those branches are left untouched on the remote; resolve manually)

set -euo pipefail

UPSTREAM_URL="https://github.com/pHequals7/muesli.git"
ORIGIN_REMOTE="origin"
UPSTREAM_REMOTE="upstream"

cd "$(git rev-parse --show-toplevel)"

if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: working tree has uncommitted changes. Stash or commit first." >&2
    exit 1
fi

if ! git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    echo "Adding $UPSTREAM_REMOTE remote → $UPSTREAM_URL"
    git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
fi

ORIGINAL_BRANCH="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"
restore_branch() {
    if [ -n "$ORIGINAL_BRANCH" ] && [ "$(git symbolic-ref --short HEAD 2>/dev/null || echo)" != "$ORIGINAL_BRANCH" ]; then
        git checkout -q "$ORIGINAL_BRANCH" 2>/dev/null || true
    fi
}
trap restore_branch EXIT

echo "Fetching $UPSTREAM_REMOTE..."
git fetch "$UPSTREAM_REMOTE" --tags --quiet
git fetch "$ORIGIN_REMOTE" --quiet

OLD_MAIN="$(git rev-parse "$ORIGIN_REMOTE/main")"
NEW_MAIN="$(git rev-parse "$UPSTREAM_REMOTE/main")"

if [ "$OLD_MAIN" = "$NEW_MAIN" ]; then
    echo "No upstream changes. main is at $NEW_MAIN."
    exit 0
fi

echo ""
echo "Upstream commits to pull ($(git rev-list --count "$OLD_MAIN..$NEW_MAIN")):"
git log --oneline "$OLD_MAIN..$NEW_MAIN" | head -20
if [ "$(git rev-list --count "$OLD_MAIN..$NEW_MAIN")" -gt 20 ]; then
    echo "  ... (more)"
fi
echo ""

echo "Fast-forwarding main..."
git checkout main -q
if ! git merge --ff-only "$UPSTREAM_REMOTE/main" --quiet; then
    echo "ERROR: main has diverged from upstream/main." >&2
    echo "       Direct commits to main are not allowed in this workflow." >&2
    echo "       Investigate manually before re-running." >&2
    exit 2
fi
git push "$ORIGIN_REMOTE" main

FEAT_BRANCHES=()
while IFS= read -r line; do
    FEAT_BRANCHES+=("$line")
done < <(git branch -r --list "$ORIGIN_REMOTE/feat/*" --format='%(refname:short)' | sed "s|^$ORIGIN_REMOTE/||")

REBASED=()
REBASE_FAILED=()
for branch in "${FEAT_BRANCHES[@]}"; do
    echo ""
    echo "=== Rebasing $branch onto main ==="
    git checkout -B "$branch" "$ORIGIN_REMOTE/$branch" -q
    if git rebase main; then
        git push --force-with-lease "$ORIGIN_REMOTE" "$branch"
        REBASED+=("$branch")
    else
        echo "Conflict — aborting rebase of $branch (will leave remote untouched)."
        git rebase --abort
        REBASE_FAILED+=("$branch")
    fi
done

echo ""
echo "=== Rebuilding release/collide ==="
git checkout -B release/collide main -q
COLLIDE_FAILED=()
for branch in "${REBASED[@]}"; do
    echo "Merging $branch..."
    if ! git merge --no-ff --no-edit "$branch"; then
        echo "Conflict merging $branch into release/collide — aborting."
        git merge --abort
        COLLIDE_FAILED+=("$branch")
    fi
done

if [ ${#COLLIDE_FAILED[@]} -eq 0 ]; then
    git push --force-with-lease "$ORIGIN_REMOTE" release/collide
else
    echo "release/collide NOT pushed because of merge conflicts above."
fi

echo ""
echo "================================"
echo "SUMMARY"
echo "================================"
echo "main: ${OLD_MAIN:0:7} → ${NEW_MAIN:0:7}"
echo "Cleanly rebased   : ${REBASED[*]:-(none)}"
echo "Rebase conflicts  : ${REBASE_FAILED[*]:-(none)}"
echo "release/collide   : ${COLLIDE_FAILED[*]:+conflicts on: ${COLLIDE_FAILED[*]}}${COLLIDE_FAILED[*]:-clean and pushed}"

if [ ${#REBASE_FAILED[@]} -gt 0 ] || [ ${#COLLIDE_FAILED[@]} -gt 0 ]; then
    exit 3
fi

echo ""
echo "All clean."
