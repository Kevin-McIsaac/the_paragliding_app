#!/bin/bash

# Read JSON input from stdin
input=$(cat)

# Background fetch if last fetch was >5 minutes ago
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
if [ -n "$GIT_DIR" ]; then
    FETCH_HEAD="$GIT_DIR/FETCH_HEAD"
    if [ -f "$FETCH_HEAD" ]; then
        LAST_FETCH=$(stat -c %Y "$FETCH_HEAD" 2>/dev/null || stat -f %m "$FETCH_HEAD" 2>/dev/null)
        NOW=$(date +%s)
        if [ $((NOW - LAST_FETCH)) -gt 300 ]; then
            git fetch --all --quiet &>/dev/null &
        fi
    else
        # No FETCH_HEAD exists, do initial fetch
        git fetch --all --quiet &>/dev/null &
    fi
fi

# Extract values using jq
MODEL_DISPLAY=$(echo "$input" | jq -r '.model.display_name')
CURRENT_DIR=$(echo "$input" | jq -r '.workspace.current_dir')

# Show git branch with color-coded status if in a git repo
GIT_BRANCH=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(git branch --show-current 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    HASH=$(git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        # Determine git status and set color
        if [ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]; then
            # Red for merge conflicts
            GIT_STATUS="🔴"
        elif [ -n "$(git status --porcelain 2>/dev/null)" ]; then
            # Yellow for dirty (uncommitted changes)
            GIT_STATUS="🟡"
        else
            # Green for clean
            GIT_STATUS="🟢"
        fi

        # Check ahead/behind remote (always show counts)
        AHEAD_BEHIND=""
        UPSTREAM=$(git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null)
        if [ -n "$UPSTREAM" ]; then
            AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
            BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
            AHEAD_BEHIND=" ↑$AHEAD ↓$BEHIND"
        fi

        GIT_BRANCH=" | $GIT_STATUS $BRANCH[$HASH]$AHEAD_BEHIND"
    fi
fi

echo "[$MODEL_DISPLAY]  ${CURRENT_DIR##*/} $GIT_BRANCH"
