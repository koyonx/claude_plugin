#!/bin/bash
# SessionStart hook: セッション開始時に前回の会話ログのパスを表示する
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CWD" ]; then
    exit 0
fi

# プロジェクトパスからディレクトリ名を生成（英数字・ハイフン・アンダースコアのみ）
PROJECT_NAME=$(echo "$CWD" | sed 's|/|_|g' | sed 's|^_||' | tr -cd 'a-zA-Z0-9_.-')
SESSION_DIR="$HOME/.claude/session-history/sessions/${PROJECT_NAME}"

if [ -d "$SESSION_DIR" ]; then
    # globで最新ファイルを取得（ls -tのパース問題を回避）
    LATEST=""
    for f in "$SESSION_DIR"/*.md; do
        [ -f "$f" ] || continue
        if [ -z "$LATEST" ] || [ "$f" -nt "$LATEST" ]; then
            LATEST="$f"
        fi
    done
    if [ -n "$LATEST" ]; then
        echo "Previous session log: $LATEST" >&2
    fi
fi

exit 0
