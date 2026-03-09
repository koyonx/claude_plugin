#!/bin/bash
# PreCompact hook: コンパクト実行前にトランスクリプトをバックアップする
set -euo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

if [ -z "$TRANSCRIPT_PATH" ] || [ -z "$SESSION_ID" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    exit 0
fi

BACKUP_DIR="$HOME/.claude/session-history/compaction-backups"
mkdir -p "$BACKUP_DIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${SESSION_ID}_${TIMESTAMP}.jsonl"

cp "$TRANSCRIPT_PATH" "$BACKUP_FILE"
echo "Backed up transcript before compaction: $BACKUP_FILE" >&2

exit 0
