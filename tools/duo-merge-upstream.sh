#!/bin/bash
# Brings the original LinPad project's fixes (github.com/fspecii/LinPad, branch main) into
# this fork's duo branch, as a merge commit. See DUO-UPDATING.md.
#   tools/duo-merge-upstream.sh          fetch, merge, report
#   tools/duo-merge-upstream.sh --check  only say how many new upstream commits there are
set -euo pipefail
cd "$(dirname "$0")/.."
UPSTREAM_URL=https://github.com/fspecii/LinPad.git

git remote get-url upstream >/dev/null 2>&1 || git remote add upstream "$UPSTREAM_URL"
git fetch --quiet upstream main

new=$(git rev-list --count HEAD..upstream/main)
if [ "$new" -eq 0 ]; then
    echo "Already up to date: no new changes in fspecii/LinPad."
    exit 0
fi
echo "fspecii/LinPad has $new new commit(s):"
git log --oneline HEAD..upstream/main | head -30
[ "${1:-}" = --check ] && exit 0

if [ -n "$(git status --porcelain)" ]; then
    echo "You have unsaved changes. Commit them (or ask Claude Code to) before merging." >&2
    exit 1
fi
branch=$(git rev-parse --abbrev-ref HEAD)
if [ "$branch" != duo ]; then
    echo "Switch to the duo branch first: git checkout duo" >&2
    exit 1
fi

if git merge --no-edit -m "Merge fixes from fspecii/LinPad" upstream/main; then
    echo
    echo "Merged cleanly. Build and test the app, then: git push"
else
    echo
    echo "These files changed in both LinPad and LinPad Duo and need a decision:"
    git diff --name-only --diff-filter=U
    echo
    echo "Ask Claude Code: \"Resolve the merge conflicts from fspecii/LinPad and explain each one.\""
    echo "To give up on this merge instead: git merge --abort"
    exit 1
fi
