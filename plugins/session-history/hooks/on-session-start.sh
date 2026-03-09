#!/bin/bash
# SessionStart hook: セッション開始時に前回の会話ログのパスを表示する
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CWD" ]; then
    exit 0
fi

# プロジェクトパスからディレクトリ名を生成
PROJECT_NAME=$(echo "$CWD" | sed 's|/|_|g' | sed 's|^_||')
SESSION_DIR="$HOME/.claude/session-history/sessions/${PROJECT_NAME}"

if [ -d "$SESSION_DIR" ]; then
    LATEST=$(ls -t "$SESSION_DIR"/*.md 2>/dev/null | head -1)
    if [ -n "$LATEST" ]; then
        echo "Previous session log: $LATEST" >&2
    fi
fi

exit 0
