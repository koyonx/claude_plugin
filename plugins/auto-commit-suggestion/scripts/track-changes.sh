#!/bin/bash
# PostToolUse hook: ファイル変更を追跡し、一定数に達したらコミットを提案する
set -euo pipefail

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty') || exit 0
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty') || exit 0

if [ -z "$TOOL_NAME" ] || [ -z "$SESSION_ID" ]; then
    exit 0
fi

# session_idをサニタイズ
SAFE_SESSION_ID=$(echo "$SESSION_ID" | tr -cd 'a-zA-Z0-9-')
if [ -z "$SAFE_SESSION_ID" ]; then
    exit 0
fi

COUNTER_DIR="$HOME/.claude/auto-commit-suggestion"
mkdir -p "$COUNTER_DIR"
COUNTER_FILE="${COUNTER_DIR}/${SAFE_SESSION_ID}.count"

# コミット閾値（デフォルト5）
THRESHOLD="${AUTO_COMMIT_THRESHOLD:-5}"

# git commitが検出されたらカウンターをリセット
if [ "$TOOL_NAME" = "Bash" ]; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty') || true
    if echo "$COMMAND" | grep -q 'git commit'; then
        echo "0" > "$COUNTER_FILE"
        exit 0
    fi
    # Bash以外のファイル変更でなければスキップ
    exit 0
fi

# Write/Editの場合のみカウント
if [ "$TOOL_NAME" != "Write" ] && [ "$TOOL_NAME" != "Edit" ]; then
    exit 0
fi

# カウンターを読み込み・インクリメント
CURRENT=0
if [ -f "$COUNTER_FILE" ]; then
    CURRENT=$(cat "$COUNTER_FILE" 2>/dev/null || echo 0)
    # 数値でなければリセット
    if ! echo "$CURRENT" | grep -q '^[0-9]*$'; then
        CURRENT=0
    fi
fi

CURRENT=$((CURRENT + 1))
echo "$CURRENT" > "$COUNTER_FILE"

# 閾値に達したら提案
if [ "$CURRENT" -ge "$THRESHOLD" ]; then
    FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // "unknown"') || true
    echo "" >&2
    echo "=== auto-commit-suggestion ===" >&2
    echo "${CURRENT} files changed in this session. Consider committing your work." >&2
    echo "Latest change: ${FILE_PATH}" >&2
    echo "==============================" >&2
    echo "" >&2
fi

exit 0
