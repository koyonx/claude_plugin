#!/bin/bash
# SessionStart hook (startup|resume): 未読の引き継ぎメモがあれば通知する
set -euo pipefail

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$CWD" ]; then
    exit 0
fi

DATA_DIR="$HOME/.claude/session-handoff"
if [ ! -d "$DATA_DIR" ]; then
    exit 0
fi

# プロジェクト名を生成
PROJECT_NAME=$(printf '%s' "$CWD" | tr -cd 'a-zA-Z0-9/_.-' | sed 's|/|_|g' | sed 's|^_||')
if [ -z "$PROJECT_NAME" ]; then
    PROJECT_NAME="default"
fi

# 同一プロジェクトの未読メモを検索
PENDING_COUNT=0
LATEST_ID=""
LATEST_TIME=""

while IFS= read -r note_file; do
    [ -z "$note_file" ] && continue
    NOTE_PROJECT=$(jq -r '.project_name // ""' "$note_file" 2>/dev/null)
    NOTE_STATUS=$(jq -r '.status // ""' "$note_file" 2>/dev/null)

    if [ "$NOTE_PROJECT" = "$PROJECT_NAME" ] && [ "$NOTE_STATUS" = "pending" ]; then
        PENDING_COUNT=$((PENDING_COUNT + 1))
        LATEST_ID=$(jq -r '.session_id // ""' "$note_file" 2>/dev/null)
        LATEST_TIME=$(jq -r '.display_time // ""' "$note_file" 2>/dev/null)
    fi
done < <(find "$DATA_DIR" -maxdepth 1 -name "*.json" ! -name "latest_*" -type f 2>/dev/null | sort -r | head -10)

if [ "$PENDING_COUNT" -gt 0 ]; then
    echo "" >&2
    echo "=== session-handoff ===" >&2
    echo "Pending handoff note(s): ${PENDING_COUNT}" >&2
    if [ -n "$LATEST_ID" ]; then
        echo "Latest: ${LATEST_ID} (${LATEST_TIME})" >&2
        echo "Use '/handoff latest' or '/handoff ${LATEST_ID}' to load." >&2
    fi
    echo "========================" >&2
fi

exit 0
