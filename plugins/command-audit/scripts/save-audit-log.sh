#!/bin/bash
# Stop hook: セッション終了時にコマンド監査ログのサマリーを表示する
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0

if [ -z "$SESSION_ID" ]; then
    exit 0
fi

# session_idをサニタイズ
SAFE_SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [ -z "$SAFE_SESSION_ID" ]; then
    exit 0
fi

LOG_DIR="$HOME/.claude/command-audit"
SESSION_LOG="${LOG_DIR}/${SAFE_SESSION_ID}.jsonl"

if [ ! -f "$SESSION_LOG" ]; then
    exit 0
fi

# JSONLの妥当性チェック
if ! head -1 "$SESSION_LOG" | jq empty 2>/dev/null; then
    exit 0
fi

# 統計を計算
TOTAL_COMMANDS=$(wc -l < "$SESSION_LOG" | tr -d ' ')
WARNED_COUNT=$(grep -c '"warned"' "$SESSION_LOG" 2>/dev/null || echo 0)

if [ "$TOTAL_COMMANDS" -eq 0 ]; then
    exit 0
fi

echo "" >&2
echo "=== command-audit: Session Summary ===" >&2
echo "Commands executed: ${TOTAL_COMMANDS}" >&2

if [ "$WARNED_COUNT" -gt 0 ]; then
    echo "Dangerous commands warned: ${WARNED_COUNT}" >&2
    echo "" >&2
    echo "Warned commands:" >&2
    grep '"warned"' "$SESSION_LOG" 2>/dev/null \
        | jq -r '"  [\(.timestamp)] \(.command)"' 2>/dev/null \
        | head -10 >&2
    if [ "$WARNED_COUNT" -gt 10 ]; then
        echo "  ... and $((WARNED_COUNT - 10)) more" >&2
    fi
fi

echo "Log: ${SESSION_LOG}" >&2
echo "========================================" >&2

# 古いログファイルの整理（30日以上前のものを削除）
find "$LOG_DIR" -name "*.jsonl" -mtime +30 -delete 2>/dev/null || true

exit 0
