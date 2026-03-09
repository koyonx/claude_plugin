#!/bin/bash
# PostToolUse hook: ファイル変更後にdiffを保存する
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0

if [ -z "$SESSION_ID" ] || [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

SAFE_SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [ -z "$SAFE_SESSION_ID" ]; then
    exit 0
fi

SNAPSHOT_DIR="$HOME/.claude/diff-snapshots/${SAFE_SESSION_ID}"
if [ ! -d "$SNAPSHOT_DIR" ]; then
    exit 0
fi

SAFE_NAME=$(echo "$FILE_PATH" | tr '/' '_' | tr -cd 'a-zA-Z0-9_.-')

# 最新のスナップショットを見つける
LATEST_SNAPSHOT=""
for f in "$SNAPSHOT_DIR"/*_"${SAFE_NAME}".snapshot; do
    [ -f "$f" ] || continue
    if [ -z "$LATEST_SNAPSHOT" ] || [ "$f" -nt "$LATEST_SNAPSHOT" ]; then
        LATEST_SNAPSHOT="$f"
    fi
done

if [ -z "$LATEST_SNAPSHOT" ]; then
    exit 0
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DIFF_FILE="${SNAPSHOT_DIR}/${TIMESTAMP}_${SAFE_NAME}.diff"

# diff生成（差分がなくても正常終了）
diff -u "$LATEST_SNAPSHOT" "$FILE_PATH" > "$DIFF_FILE" 2>/dev/null || true

# diffが空なら削除
if [ ! -s "$DIFF_FILE" ]; then
    rm -f "$DIFF_FILE"
fi

exit 0
