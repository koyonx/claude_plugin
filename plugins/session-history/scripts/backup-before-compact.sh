#!/bin/bash
# PreCompact hook: コンパクト実行前にトランスクリプトをバックアップする
set -euo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ -z "$SESSION_ID" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

# 入力バリデーション: シンボリックリンクを解決してから.claude配下であることを確認
CLAUDE_DIR="$HOME/.claude"
RESOLVED_PATH=$(realpath "$TRANSCRIPT_PATH" 2>/dev/null) || exit 0
case "$RESOLVED_PATH" in
    "$CLAUDE_DIR"/*)
        ;;
    *)
        echo "Invalid transcript path: not under ~/.claude" >&2
        exit 0
        ;;
esac

# session_idにパス区切り文字が含まれていないことを確認
if echo "$SESSION_ID" | grep -q '[/\\]'; then
    echo "Invalid session_id: contains path separators" >&2
    exit 0
fi

# ファイルサイズ制限 (100MB)
MAX_SIZE=$((100 * 1024 * 1024))
FILE_SIZE=$(stat -f%z "$RESOLVED_PATH" 2>/dev/null || stat -c%s "$RESOLVED_PATH" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    echo "Transcript too large (${FILE_SIZE} bytes). Skipping backup." >&2
    exit 0
fi

BACKUP_DIR="$HOME/.claude/session-history/compaction-backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
# session_idから英数字とハイフンのみ抽出
SAFE_SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
BACKUP_FILE="${BACKUP_DIR}/${SAFE_SESSION_ID}_${TIMESTAMP}.jsonl"

cp "$RESOLVED_PATH" "$BACKUP_FILE"
echo "Backed up transcript before compaction: $BACKUP_FILE" >&2

exit 0
