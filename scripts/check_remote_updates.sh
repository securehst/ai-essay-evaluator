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
    # reports the outcome through its exit status: 0 for a clean merge, 1 on
    # conflict. Git specifies only those two; anything else means the merge
    # could not run, which this hook cannot interpret — so it blocks the push
    # rather than guessing.
    #
    # The previous check grepped the deprecated three-arg form for '^<<<<<<< '.
    # That form exits 0 even on conflict and prints its markers inside a diff,
    # so the real line is '+<<<<<<< .our' and the anchored pattern could never
    # match: every conflicting divergence was reported as clean.
    MERGE_STATUS=0
    git merge-tree --write-tree @ "origin/$BRANCH" >/dev/null 2>&1 || MERGE_STATUS=$?

    if [ "$MERGE_STATUS" -gt 1 ]; then
        echo "ERROR: Could not test-merge origin/$BRANCH (git merge-tree exited $MERGE_STATUS)."
        echo "This hook requires git 2.38 or newer."
        echo "  Yours: $(git --version)"
        exit 1
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
