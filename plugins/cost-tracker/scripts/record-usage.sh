#!/bin/bash
# Stop hook: セッションのトークン使用量を記録する
set -euo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty') || exit 0
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

if [ -z "$TRANSCRIPT_PATH" ] || [ -z "$SESSION_ID" ]; then
    exit 0
fi

# transcript_pathの検証
CLAUDE_DIR="$HOME/.claude"
RESOLVED_PATH=$(realpath "$TRANSCRIPT_PATH" 2>/dev/null) || exit 0
case "$RESOLVED_PATH" in
    "$CLAUDE_DIR"/*)
        ;;
    *)
        exit 0
        ;;
esac

# ファイルサイズ制限 (100MB)
MAX_SIZE=$((100 * 1024 * 1024))
FILE_SIZE=$(stat -f%z "$RESOLVED_PATH" 2>/dev/null || stat -c%s "$RESOLVED_PATH" 2>/dev/null || echo 0)
if [ "$FILE_SIZE" -gt "$MAX_SIZE" ]; then
    exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
python3 "${PLUGIN_ROOT}/scripts/usage_parser.py" \
    --transcript "$RESOLVED_PATH" \
    --session-id "$SESSION_ID" \
    --cwd "$CWD" 2>&1 || true

exit 0
