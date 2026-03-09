#!/bin/bash
# PreToolUse hook: ファイル変更前にスナップショットを保存する
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input // empty') || exit 0
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty') || exit 0

if [ -z "$SESSION_ID" ] || [ -z "$FILE_PATH" ]; then
    exit 0
fi

# ファイルが存在しない場合はスキップ（新規作成）
if [ ! -f "$FILE_PATH" ]; then
    exit 0
fi

# ファイルサイズ制限 (50MB)
MAX_SIZE=$((50 * 1024 * 1024))
FILE_SIZE=$(stat -f%z "$FILE_PATH" 2>/dev/null || stat -c%s "$FILE_PATH" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    echo "File too large for snapshot: ${FILE_PATH}" >&2
    exit 0
fi

# スナップショット保存先
SAFE_SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [ -z "$SAFE_SESSION_ID" ]; then
    exit 0
fi

SNAPSHOT_DIR="$HOME/.claude/diff-snapshots/${SAFE_SESSION_ID}"
mkdir -p "$SNAPSHOT_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
# ファイルパスをサニタイズしてフラットなファイル名にする
SAFE_NAME=$(echo "$FILE_PATH" | tr '/' '_' | tr -cd 'a-zA-Z0-9_.-')
SNAPSHOT_FILE="${SNAPSHOT_DIR}/${TIMESTAMP}_${SAFE_NAME}.snapshot"

cp "$FILE_PATH" "$SNAPSHOT_FILE"

# メタデータを保存
cat > "${SNAPSHOT_FILE}.meta" <<METAEOF
{
    "original_path": $(echo "$FILE_PATH" | jq -Rs .),
    "timestamp": "${TIMESTAMP}",
    "session_id": "${SAFE_SESSION_ID}",
    "type": "pre-snapshot"
}
METAEOF

exit 0
