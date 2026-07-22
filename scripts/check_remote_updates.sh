#!/bin/bash
set -e

echo "Checking for updates from remote repository..."

# Get the current branch
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Fetch the latest changes
git fetch origin

# A branch with no remote counterpart cannot be behind one. Without this guard
# the rev-parse below fails under `set -e`, so the hook rejected the first push
# of every new branch.
if ! git rev-parse --verify --quiet "origin/$BRANCH" >/dev/null; then
    echo "origin/$BRANCH does not exist yet — first push of a new branch. Proceeding with push..."
    exit 0
fi

# Check if the local branch is behind the remote branch
LOCAL=$(git rev-parse @)
REMOTE=$(git rev-parse "origin/$BRANCH")
BASE=$(git merge-base @ "origin/$BRANCH")

if [ "$LOCAL" = "$REMOTE" ]; then
    echo "Repository is up to date with origin/$BRANCH. Proceeding with push..."
    exit 0
elif [ "$LOCAL" = "$BASE" ]; then
    echo "ERROR: Local $BRANCH is behind origin/$BRANCH."
    echo "Please pull the latest changes before pushing:"
    echo "  git pull origin $BRANCH"
    exit 1
else
    echo "Local $BRANCH has diverged from origin/$BRANCH."
    echo "Checking if merging is possible..."

    # Try to merge without committing. `merge-tree --write-tree` (git 2.38+)
    # exits 0 for a clean merge and 1 on conflict; any other status means the
    # flag is unsupported, so fall back to the deprecated three-arg form. That
    # form prints its markers as part of a diff, so they carry a leading '+' —
    # the previous `^<<<<<<< ` pattern anchored past it and never matched, which
    # meant conflicts were always reported as clean.
    MERGE_STATUS=0
    git merge-tree --write-tree @ "origin/$BRANCH" >/dev/null 2>&1 || MERGE_STATUS=$?

    if [ "$MERGE_STATUS" -gt 1 ]; then
        MERGE_STATUS=0
        git merge-tree "$BASE" @ "origin/$BRANCH" | grep -q '^+<<<<<<<' && MERGE_STATUS=1
    fi

    if [ "$MERGE_STATUS" -ne 0 ]; then
        echo "ERROR: Merging would cause conflicts."
        echo "Please pull and resolve conflicts before pushing:"
        echo "  git pull origin $BRANCH"
        exit 1
    else
        echo "Merging is possible without conflicts."
        echo "Consider pulling changes before pushing:"
        echo "  git pull origin $BRANCH"
        # We can either force an exit here or allow the push
        # exit 1  # Uncomment to force pull before push
        exit 0
    fi
fi
