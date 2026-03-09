#!/bin/bash
# Stop hook: Claudeの応答完了時にトランスクリプトを読みやすい形式で保存する
# python3の失敗でClaudeの動作を妨げないようexit 0で終了する
set -euo pipefail

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty') || exit 0
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0
CWD=$(echo "$INPUT" | jq -r '.cwd // empty') || exit 0

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

# CWDバリデーション: 安全な文字のみで構成されていることを確認
# (Python側のsanitize_filenameでもフィルタされるが、防御を二重化)
CWD_SANITIZED=$(echo "$CWD" | tr -cd 'a-zA-Z0-9/_. -')
if [ "$CWD" != "$CWD_SANITIZED" ]; then
    echo "Invalid cwd: contains unexpected characters" >&2
    exit 0
fi

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
python3 "${PLUGIN_ROOT}/scripts/transcript_parser.py" \
    --transcript "$RESOLVED_PATH" \
    --session-id "$SESSION_ID" \
    --cwd "$CWD" 2>&1 || true

exit 0
