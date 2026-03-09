#!/bin/bash
# Stop hook: Claudeの応答完了時にトランスクリプトを読みやすい形式で保存する
# python3の失敗でClaudeの動作を妨げないようexit 0で終了する
set -uo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

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

# CWDバリデーション: パストラバーサル文字を含まないことを確認
if echo "$CWD" | grep -q '\.\.'; then
    echo "Invalid cwd: contains path traversal" >&2
    exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
python3 "${PLUGIN_ROOT}/scripts/transcript_parser.py" \
    --transcript "$RESOLVED_PATH" \
    --session-id "$SESSION_ID" \
    --cwd "$CWD" 2>&1 || true

exit 0
